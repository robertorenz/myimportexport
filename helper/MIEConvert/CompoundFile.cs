using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace MIEConvert
{
    /// <summary>Minimal OLE2 / Compound File Binary reader and single-stream writer.</summary>
    public static class CompoundFile
    {
        const uint FREESECT = 0xFFFFFFFF, ENDOFCHAIN = 0xFFFFFFFE, FATSECT = 0xFFFFFFFD, DIFSECT = 0xFFFFFFFC, NOSTREAM = 0xFFFFFFFF;
        static readonly byte[] Signature = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };

        public static bool IsCompoundFile(byte[] d)
        {
            if (d.Length < 512) return false;
            for (int i = 0; i < 8; i++) if (d[i] != Signature[i]) return false;
            return true;
        }

        /// <summary>Returns the content of the first stream whose name matches one of <paramref name="names"/>.</summary>
        public static byte[] ReadStream(byte[] d, params string[] names)
        {
            if (!IsCompoundFile(d)) throw new MieException("The file is not an Excel 97-2003 (.xls) workbook.");
            int secShift = BitConverter.ToUInt16(d, 0x1E);
            int miniShift = BitConverter.ToUInt16(d, 0x20);
            if (secShift < 7 || secShift > 16) throw new MieException("Corrupt .xls file (bad sector size).");
            int secSize = 1 << secShift;
            int miniSize = 1 << miniShift;
            uint numFat = BitConverter.ToUInt32(d, 0x2C);
            uint firstDir = BitConverter.ToUInt32(d, 0x30);
            uint miniCutoff = BitConverter.ToUInt32(d, 0x38);
            uint firstMiniFat = BitConverter.ToUInt32(d, 0x3C);
            uint firstDifat = BitConverter.ToUInt32(d, 0x44);
            long nSectors = (d.Length - secSize) / secSize + 1;

            Func<uint, int> off = sid => (int)((sid + 1L) * secSize);

            // FAT sector ids from the header DIFAT and the DIFAT chain
            var fatSecs = new List<uint>();
            for (int i = 0; i < 109 && fatSecs.Count < numFat; i++)
            {
                uint s = BitConverter.ToUInt32(d, 0x4C + i * 4);
                if (s == FREESECT || s == ENDOFCHAIN) break;
                fatSecs.Add(s);
            }
            uint dif = firstDifat;
            int guard = 0;
            while (dif != ENDOFCHAIN && dif != FREESECT && fatSecs.Count < numFat && guard++ < 100000)
            {
                int o = off(dif);
                if (o + secSize > d.Length) break;
                int per = secSize / 4 - 1;
                for (int i = 0; i < per && fatSecs.Count < numFat; i++)
                {
                    uint s = BitConverter.ToUInt32(d, o + i * 4);
                    if (s != FREESECT) fatSecs.Add(s);
                }
                dif = BitConverter.ToUInt32(d, o + per * 4);
            }
            int perSec = secSize / 4;
            var fat = new uint[fatSecs.Count * perSec];
            for (int k = 0; k < fatSecs.Count; k++)
            {
                int o = off(fatSecs[k]);
                for (int i = 0; i < perSec; i++)
                    fat[k * perSec + i] = o + i * 4 + 4 <= d.Length ? BitConverter.ToUInt32(d, o + i * 4) : FREESECT;
            }

            Func<uint, byte[]> readChain = start =>
            {
                var ms = new MemoryStream();
                uint s = start;
                int g = 0;
                while (s != ENDOFCHAIN && s != FREESECT && s < fat.Length && g++ <= nSectors)
                {
                    int o = off(s);
                    int len = Math.Min(secSize, d.Length - o);
                    if (len <= 0) break;
                    ms.Write(d, o, len);
                    s = fat[s];
                }
                return ms.ToArray();
            };

            byte[] dir = readChain(firstDir);
            int nEntries = dir.Length / 128;
            if (nEntries == 0) throw new MieException("Corrupt .xls file (no directory).");
            uint rootStart = BitConverter.ToUInt32(dir, 0x74);
            long rootSize = BitConverter.ToUInt32(dir, 0x78);

            for (int pass = 0; pass < names.Length; pass++)
            {
                for (int e = 1; e < nEntries; e++)
                {
                    int b = e * 128;
                    int nameLen = BitConverter.ToUInt16(dir, b + 0x40);
                    byte type = dir[b + 0x42];
                    if (type != 2 || nameLen < 2 || nameLen > 64) continue;
                    string name = Encoding.Unicode.GetString(dir, b, nameLen - 2);
                    if (!string.Equals(name, names[pass], StringComparison.OrdinalIgnoreCase)) continue;
                    uint start = BitConverter.ToUInt32(dir, b + 0x74);
                    long size = BitConverter.ToUInt32(dir, b + 0x78);
                    byte[] data;
                    if (size < miniCutoff)
                    {
                        byte[] mini = readChain(rootStart);
                        byte[] miniFatBytes = readChain(firstMiniFat);
                        var mfat = new uint[miniFatBytes.Length / 4];
                        for (int i = 0; i < mfat.Length; i++) mfat[i] = BitConverter.ToUInt32(miniFatBytes, i * 4);
                        var ms = new MemoryStream();
                        uint s = start;
                        int g = 0;
                        while (s != ENDOFCHAIN && s != FREESECT && s < mfat.Length && g++ <= mfat.Length)
                        {
                            int o = (int)(s * miniSize);
                            if (o >= mini.Length) break;
                            ms.Write(mini, o, Math.Min(miniSize, mini.Length - o));
                            s = mfat[s];
                        }
                        data = ms.ToArray();
                    }
                    else data = readChain(start);
                    if (data.Length > size) Array.Resize(ref data, (int)size);
                    return data;
                }
            }
            return null;
        }

        /// <summary>Writes a compound file (version 3, 512-byte sectors) holding one stream.
        /// The stream must be at least 4096 bytes so that it lives in regular sectors.</summary>
        public static void WriteSingleStream(Stream output, string streamName, byte[] stream)
        {
            const int SS = 512;
            if (stream.Length < 4096) throw new InvalidOperationException("stream must be padded to 4096 bytes");
            int nStream = (stream.Length + SS - 1) / SS;
            int nDir = 1;
            int nFat = 1, nDifat = 0;
            while (true)
            {
                nDifat = nFat > 109 ? (nFat - 109 + 126) / 127 : 0;
                int total = nStream + nDir + nFat + nDifat;
                int need = (total + 127) / 128;
                if (need <= nFat) break;
                nFat = need;
            }
            int total2 = nStream + nDir + nFat + nDifat;
            // layout: [stream][dir][fat][difat]
            uint dirStart = (uint)nStream;
            uint fatStart = dirStart + (uint)nDir;
            uint difatStart = fatStart + (uint)nFat;

            var fat = new uint[nFat * 128];
            for (int i = 0; i < fat.Length; i++) fat[i] = FREESECT;
            for (int i = 0; i < nStream; i++) fat[i] = i == nStream - 1 ? ENDOFCHAIN : (uint)(i + 1);
            fat[dirStart] = ENDOFCHAIN;
            for (int i = 0; i < nFat; i++) fat[fatStart + i] = FATSECT;
            for (int i = 0; i < nDifat; i++) fat[difatStart + i] = DIFSECT;

            var w = new BinaryWriter(output);
            // header
            var h = new byte[SS];
            Array.Copy(Signature, h, 8);
            PutU16(h, 0x18, 0x003E);
            PutU16(h, 0x1A, 0x0003);
            PutU16(h, 0x1C, 0xFFFE);
            PutU16(h, 0x1E, 9);
            PutU16(h, 0x20, 6);
            PutU32(h, 0x28, 0);              // number of directory sectors (0 for v3)
            PutU32(h, 0x2C, (uint)nFat);
            PutU32(h, 0x30, dirStart);
            PutU32(h, 0x34, 0);
            PutU32(h, 0x38, 4096);
            PutU32(h, 0x3C, ENDOFCHAIN);
            PutU32(h, 0x40, 0);
            PutU32(h, 0x44, nDifat > 0 ? difatStart : ENDOFCHAIN);
            PutU32(h, 0x48, (uint)nDifat);
            for (int i = 0; i < 109; i++) PutU32(h, 0x4C + i * 4, i < nFat ? fatStart + (uint)i : FREESECT);
            w.Write(h);

            // stream sectors
            w.Write(stream);
            int pad = nStream * SS - stream.Length;
            if (pad > 0) w.Write(new byte[pad]);

            // directory sector: root + stream + 2 empty
            var dir = new byte[SS];
            WriteDirEntry(dir, 0, "Root Entry", 5, NOSTREAM, NOSTREAM, 1, ENDOFCHAIN, 0);
            WriteDirEntry(dir, 128, streamName, 2, NOSTREAM, NOSTREAM, NOSTREAM, 0, (uint)stream.Length);
            for (int e = 2; e < 4; e++)
            {
                int b = e * 128;
                PutU32(dir, b + 0x44, NOSTREAM);
                PutU32(dir, b + 0x48, NOSTREAM);
                PutU32(dir, b + 0x4C, NOSTREAM);
            }
            w.Write(dir);

            // FAT sectors
            var fb = new byte[nFat * SS];
            for (int i = 0; i < fat.Length; i++) PutU32(fb, i * 4, fat[i]);
            w.Write(fb);

            // DIFAT sectors
            for (int k = 0; k < nDifat; k++)
            {
                var db = new byte[SS];
                for (int i = 0; i < 127; i++)
                {
                    int fi = 109 + k * 127 + i;
                    PutU32(db, i * 4, fi < nFat ? fatStart + (uint)fi : FREESECT);
                }
                PutU32(db, 127 * 4, k == nDifat - 1 ? ENDOFCHAIN : difatStart + (uint)k + 1);
                w.Write(db);
            }
            w.Flush();
            if (total2 <= 0) throw new InvalidOperationException();
        }

        static void WriteDirEntry(byte[] b, int o, string name, byte type, uint left, uint right, uint child, uint start, uint size)
        {
            byte[] n = Encoding.Unicode.GetBytes(name);
            Array.Copy(n, 0, b, o, Math.Min(n.Length, 62));
            PutU16(b, o + 0x40, (ushort)(Math.Min(n.Length, 62) + 2));
            b[o + 0x42] = type;
            b[o + 0x43] = 1; // black
            PutU32(b, o + 0x44, left);
            PutU32(b, o + 0x48, right);
            PutU32(b, o + 0x4C, child);
            PutU32(b, o + 0x74, start);
            PutU32(b, o + 0x78, size);
            PutU32(b, o + 0x7C, 0);
        }

        static void PutU16(byte[] b, int o, int v) { b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); }
        static void PutU32(byte[] b, int o, uint v) { b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24); }
    }
}
