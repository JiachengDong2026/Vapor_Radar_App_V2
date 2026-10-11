using System;
using System.IO;
using System.Threading;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;
using CyUSB;

// Only transports bytes. Register policy, CRC and acknowledgements are in Qt.
// Uses the existing Cypress driver; no device firmware or driver changes.
class VaporUsbBridge
{
    static volatile bool stopping;
    static Exception readerError;
    static int ReadExact(Stream s, byte[] b, int n) {
        int used=0;
        while(used<n) { int r=s.Read(b,used,n-used); if(r==0)return used; used+=r; }
        return used;
    }
    [STAThread] static int Main(string[] args) {
        USBDeviceList devices=null; Thread reader=null; TcpListener listener=null; TcpClient client=null;
        try {
            devices=new USBDeviceList(CyConst.DEVICES_CYUSB);
            CyUSBDevice device=null; int matches=0;
            foreach(USBDevice d in devices) {
                CyUSBDevice c=d as CyUSBDevice;
                if(c!=null && c.VendorID==0x04b4 && c.ProductID==0x00f1) { device=c; matches++; }
            }
            if(matches!=1)throw new IOException("Expected one FX3 04B4:00F1; found "+matches);
            CyBulkEndPoint input=device.EndPointOf(0x86) as CyBulkEndPoint;
            CyBulkEndPoint output=device.EndPointOf(0x02) as CyBulkEndPoint;
            if(input==null || output==null)throw new IOException("Bulk endpoints 86/02 absent");
            var ctrl=device.ControlEndPt;
            ctrl.Target=CyConst.TGT_DEVICE; ctrl.ReqType=CyConst.REQ_VENDOR;
            ctrl.Direction=CyConst.DIR_FROM_DEVICE;ctrl.ReqCode=0xb1;
            ctrl.Value=0;ctrl.Index=0;ctrl.TimeOut=1500;
            byte[] diag=new byte[32];int count=32;
            if(!ctrl.XferData(ref diag,ref count)||count!=32||BitConverter.ToUInt32(diag,0)!=0x31305047)
                throw new IOException("GP01 firmware signature not verified");
            if(args.Length==1 && args[0]=="--probe"){Console.Error.WriteLine("READY GP01 04B4:00F1");return 0;}
            input.TimeOut=250;output.TimeOut=1000;
            Stream stdout=Console.OpenStandardOutput();
            bool socketMode=args.Length==2 && args[0]=="--socket";
            if(socketMode){listener=new TcpListener(IPAddress.Loopback,0);listener.Start(1);}
            var commands=new BlockingCollection<byte[]>(32);
            reader=new Thread(delegate() {
                try {
                    TextReader commandReader=Console.In;
                    if(socketMode){
                        client=listener.AcceptTcpClient();client.NoDelay=true;
                        commandReader=new StreamReader(client.GetStream(),Encoding.ASCII);
                        if(commandReader.ReadLine()!=args[1])throw new IOException("Local IPC token mismatch");
                    }
                    while(!stopping) {
                        string line=commandReader.ReadLine();if(line==null)break;
                        if(line.Length>5500)throw new IOException("IPC command line too long");
                        byte[] command=Convert.FromBase64String(line);
                        int size=command.Length;
                        if(size<44||size>4096)throw new IOException("IPC command size out of bounds");
                        if(BitConverter.ToUInt32(command,0)!=0x31504c56||command[6]!=1)
                            throw new IOException("IPC requires VLP command frame");
                        commands.Add(command);
                        if(Environment.GetEnvironmentVariable("VAPOR_TRACE_COMMANDS")!=null)Console.Error.WriteLine("IPC seq="+BitConverter.ToUInt32(command,12));
                    }
                } catch(Exception e) { readerError=e; }
                finally {commands.CompleteAdding();}
            });
            reader.IsBackground=true;reader.Start();
            Console.Error.WriteLine("READY GP01 04B4:00F1"+(socketMode?" PORT="+((IPEndPoint)listener.LocalEndpoint).Port:""));
            byte[] buffer=new byte[16384];
            while(!stopping) {
                byte[] command;
                while(commands.TryTake(out command)) {
                    int size=command.Length,sent=size;
                    if(!output.XferData(ref command,ref sent)||sent!=size)
                        throw new IOException("USB OUT failed; command not retried");
                    if(Environment.GetEnvironmentVariable("VAPOR_TRACE_COMMANDS")!=null)Console.Error.WriteLine("TX seq="+BitConverter.ToUInt32(command,12)+" bytes="+sent);
                }
                if(commands.IsCompleted)break;
                int n=buffer.Length;bool ok=input.XferData(ref buffer,ref n);
                if(!ok){if(n!=0)throw new IOException("Failed IN with ambiguous partial bytes: "+n);continue;}
                if(n<0||n>buffer.Length)throw new IOException("Invalid USB IN length");
                if(n>0){stdout.Write(buffer,0,n);stdout.Flush();}
            }
            if(readerError!=null)throw readerError;
            return 0;
        } catch(Exception e) {Console.Error.WriteLine("ERROR "+e.Message);return 1;}
        finally {
            stopping=true;
            if(client!=null)client.Close();
            if(listener!=null)listener.Stop();
            if(reader!=null)reader.Join(1500);
            if(devices!=null)devices.Dispose();
        }
    }
}
