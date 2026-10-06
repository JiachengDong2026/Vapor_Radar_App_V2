using System;
using System.Diagnostics;
using System.IO;
using CyUSB;

// Bounded capture with optional validated READ_REG request. No register writes or resets.
class CaptureIn
{
    static void ValidateRead(byte[] data)
    {
        if (data.Length != 52 || BitConverter.ToUInt32(data, 0) != 0x31504C56 ||
            data[4] != 1 || data[5] != 0 || data[6] != 1 || data[7] != 10 ||
            BitConverter.ToUInt32(data, 8) != 52 || BitConverter.ToUInt16(data, 16) != 1 ||
            BitConverter.ToUInt16(data, 18) != 2 || BitConverter.ToUInt32(data, 36) != 8)
            throw new IOException("Only a 52-byte SYSTEM READ_REG command is accepted.");
        uint address = BitConverter.ToUInt32(data, 40), count = BitConverter.ToUInt32(data, 44);
        if (!((address == 0 && count == 5) || (address == 0x110 && count == 4) ||
              (address == 0x8000 && count == 16) || (address == 0x48 && count == 2) ||
              (address == 0x7000 && count == 8)))
            throw new IOException("Read range not in the diagnostic allowlist.");
        uint crc = 0xFFFFFFFF;
        for (int i = 0; i < data.Length - 4; ++i)
        {
            crc ^= data[i];
            for (int bit = 0; bit < 8; ++bit)
                crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xEDB88320u : 0u);
        }
        if ((crc ^ 0xFFFFFFFF) != BitConverter.ToUInt32(data, 48))
            throw new IOException("READ_REG CRC mismatch.");
    }

    static byte[] Diagnostic(CyUSBDevice device, byte request, string path)
    {
        CyControlEndPoint ep = device.ControlEndPt;
        ep.Target = CyConst.TGT_DEVICE;
        ep.ReqType = CyConst.REQ_VENDOR;
        ep.Direction = CyConst.DIR_FROM_DEVICE;
        ep.ReqCode = request;
        ep.Value = 0;
        ep.Index = 0;
        ep.TimeOut = 1000;
        byte[] data = new byte[32];
        int count = data.Length;
        if (!ep.XferData(ref data, ref count) || count != 32)
            throw new IOException("Diagnostic failed: " + request.ToString("X2"));
        File.WriteAllBytes(path, data);
        Console.WriteLine("B{0}: {1}", request - 0xB0, BitConverter.ToString(data));
        return data;
    }

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 1 || args.Length > 2) { Console.Error.WriteLine("Usage: CaptureIn.exe NEW_OUTPUT_DIRECTORY [READ_REG_BIN]"); return 2; }
        USBDeviceList devices = null;
        try
        {
            string output = Path.GetFullPath(args[0]);
            byte[] request = args.Length == 2 ? File.ReadAllBytes(args[1]) : null;
            if (request != null) ValidateRead(request);
            if (Directory.Exists(output)) throw new IOException("Output directory already exists; choose a new capture name.");
            Directory.CreateDirectory(output);
            devices = new USBDeviceList(CyConst.DEVICES_CYUSB);
            CyUSBDevice device = null;
            int matches = 0;
            foreach (USBDevice candidate in devices)
            {
                CyUSBDevice cy = candidate as CyUSBDevice;
                if (cy != null && cy.VendorID == 0x04B4 && cy.ProductID == 0x00F1)
                { device = cy; ++matches; }
            }
            if (matches != 1) throw new IOException("Expected exactly one 04B4:00F1 device; found " + matches);
            byte[] identity = Diagnostic(device, 0xB1, Path.Combine(output, "b1_before.bin"));
            if (BitConverter.ToUInt32(identity, 0) != 0x31305047)
                throw new IOException("Device is not GP01 diagnostic firmware.");
            Diagnostic(device, 0xB0, Path.Combine(output, "b0_before.bin"));
            CyBulkEndPoint input = device.EndPointOf(0x86) as CyBulkEndPoint;
            if (input == null) throw new IOException("Bulk IN 86 is missing.");
            input.TimeOut = 500;
            if (request != null)
            {
                CyBulkEndPoint command = device.EndPointOf(0x02) as CyBulkEndPoint;
                if (command == null) throw new IOException("Bulk OUT 02 is missing.");
                command.TimeOut = 1000;
                File.WriteAllBytes(Path.Combine(output, "request.bin"), request);
                int sent = request.Length;
                if (!command.XferData(ref request, ref sent) || sent != 52)
                    throw new IOException("READ_REG transmission failed; not retried.");
                Console.WriteLine("READ_REG_SENT sequence={0}", BitConverter.ToUInt32(request, 12));
            }
            Stopwatch timer = Stopwatch.StartNew();
            int success = 0, failures = 0;
            long total = 0;
            using (FileStream raw = new FileStream(Path.Combine(output, "bulk_in.bin"), FileMode.CreateNew))
            using (StreamWriter log = new StreamWriter(Path.Combine(output, "transfers.tsv")))
            {
                log.WriteLine("index\telapsed_ms\tsuccess\tbytes\tnt_status\tusb_status");
                for (int i = 0; i < 4096 && timer.ElapsedMilliseconds < 20000; ++i)
                {
                    byte[] buffer = new byte[16384];
                    int count = buffer.Length;
                    bool ok = input.XferData(ref buffer, ref count);
                    log.WriteLine("{0}\t{1}\t{2}\t{3}\t{4:X8}\t{5:X8}",
                        i, timer.ElapsedMilliseconds, ok, count, input.NtStatus, input.UsbdStatus);
                    if (ok && count >= 0 && count <= buffer.Length)
                    {
                        raw.Write(buffer, 0, count); total += count; ++success;
                    }
                    else
                    {
                        // Do not treat an unchanged requested length as received data.
                        ++failures;
                        if (count > 0 && count <= buffer.Length)
                        {
                            byte[] uncertain = new byte[count];
                            Array.Copy(buffer, uncertain, count);
                            File.WriteAllBytes(Path.Combine(output, "failed_transfer_" + i + ".bin"), uncertain);
                        }
                        if (failures >= 8) break;
                    }
                }
            }
            Diagnostic(device, 0xB0, Path.Combine(output, "b0_after.bin"));
            Diagnostic(device, 0xB1, Path.Combine(output, "b1_after.bin"));
            Console.WriteLine("CAPTURE_DONE successful_transfers={0} failed_transfers={1} bytes={2}", success, failures, total);
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.ToString()); return 1; }
        finally { if (devices != null) devices.Dispose(); }
    }
}
