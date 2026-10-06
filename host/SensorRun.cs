using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using CyUSB;

// Serialized diagnostic reads and six sensor enable bits only.
class SensorRun
{
    USBDeviceList devices;
    CyUSBDevice device;
    CyBulkEndPoint input, output;
    FileStream raw;
    StreamWriter log;
    List<byte> pending = new List<byte>();
    HashSet<uint> touched = new HashSet<uint>();
    uint sequence = 1000, awaiting;
    ushort expected;
    byte[] reply;
    long frames, bytes, timeouts;
    string directory;
    static uint U32(byte[] b, int p) { return BitConverter.ToUInt32(b,p); }
    static uint Crc(byte[] b,int n) {
        uint c=0xffffffff;
        for(int i=0;i<n;i++) { c^=b[i]; for(int j=0;j<8;j++) c=(c>>1)^((c&1)!=0?0xedb88320u:0); }
        return c^0xffffffff;
    }
    static uint Number(string s) { return s.StartsWith("0x")?Convert.ToUInt32(s.Substring(2),16):Convert.ToUInt32(s); }
    static bool SensorControl(uint a) { return a==0x6004||a==0x6204||a==0x6304||a==0x6404||a==0x6504||a==0x6604; }
    static void Validate(string[] fields) {
        if(fields.Length==2&&fields[0]=="WAIT"&&Number(fields[1])<=600) return;
        if(fields.Length!=3) throw new Exception("Bad plan line");
        uint a=Number(fields[1]), v=Number(fields[2]);
        if(fields[0]=="W"&&SensorControl(a)&&v<=1) return;
        if(fields[0]=="W"&&a==0x6304&&v==2) return; // Local BMP reset for failed boot cleanup.
        if(fields[0]=="W"&&a==0x6310&&(v==0x76||v==0x77)) return; // Two documented I2C addresses.
        if(fields[0]=="R"&&a<=0x80fc&&(a&3)==0&&v>=1&&v<=32&&((a&255)+v*4)<=256) return;
        throw new Exception("Plan rejected: only diagnostic reads/six enable bits are supported");
    }
    void Event(string text) { Console.WriteLine(text); log.WriteLine(DateTime.UtcNow.ToString("o")+" "+text); log.Flush(); }
    void Pump() {
        byte[] b=new byte[16384];int count=b.Length;
        bool ok=input.XferData(ref b,ref count);
        if(!ok) { ++timeouts; if(count!=0) throw new IOException("Failed transfer with ambiguous partial bytes"); return; }
        if(count<0||count>b.Length) throw new IOException("Invalid transfer length");
        raw.Write(b,0,count);bytes+=count;
        for(int i=0;i<count;i++)pending.Add(b[i]);
        while(pending.Count>=40) {
            byte[] header=pending.GetRange(0,40).ToArray();
            if(U32(header,0)!=0x31504c56||header[4]!=1||header[5]!=0||header[7]!=10)throw new IOException("Invalid VLP header");
            uint n=U32(header,8);
            if(n<44||n>1048576||n!=44+U32(header,36))throw new IOException("Invalid VLP length");
            int aligned=((int)n+3)&~3;
            if(pending.Count<aligned)return;
            byte[] f=pending.GetRange(0,(int)n).ToArray();pending.RemoveRange(0,aligned);
            if(Crc(f,f.Length-4)!=U32(f,f.Length-4))throw new IOException("VLP CRC failed");
            ++frames;
            if((f[6]==2||f[6]==0x7f)&&U32(f,12)==awaiting&&BitConverter.ToUInt16(f,18)==expected&&BitConverter.ToUInt16(f,16)==1)reply=f;
        }
    }
    void Drain(int ms) { Stopwatch t=Stopwatch.StartNew();while(t.ElapsedMilliseconds<ms)Pump(); }
    byte[] Command(bool write,uint address,uint value) {
        int size=write?56:52;byte[] b=new byte[size];
        using(MemoryStream ms=new MemoryStream(b))using(BinaryWriter w=new BinaryWriter(ms)) {
            w.Write(0x31504c56u);w.Write((byte)1);w.Write((byte)0);w.Write((byte)1);w.Write((byte)10);
            w.Write((uint)size);w.Write(++sequence);w.Write((ushort)1);w.Write((ushort)(write?3:2));
            w.Write(0u);w.Write(0ul);w.Write(0u);w.Write((uint)(write?12:8));w.Write(address);w.Write(write?1u:value);
            if(write)w.Write(value);
        }
        Array.Copy(BitConverter.GetBytes(Crc(b,size-4)),0,b,size-4,4);
        awaiting=sequence;expected=(ushort)(write?3:2);reply=null;
        File.WriteAllBytes(Path.Combine(directory,"request_"+sequence+".bin"),b);
        int sent=size;
        if(write&&SensorControl(address))touched.Add(address); // Also restore if acceptance becomes uncertain.
        if(!output.XferData(ref b,ref sent)||sent!=size)throw new IOException("OUT failed; not retried");
        Stopwatch timer=Stopwatch.StartNew();
        while(reply==null&&timer.ElapsedMilliseconds<10000)Pump();
        if(reply==null)throw new IOException("No command response seq="+sequence);
        byte[] result=reply;
        File.WriteAllBytes(Path.Combine(directory,"response_"+sequence+".bin"),result);
        if(result.Length<48||result[6]!=2||U32(result,40)!=0)throw new IOException("Command rejected seq="+sequence+" status="+U32(result,40));
        if(write)Event("WRITE seq="+sequence+" addr="+address.ToString("X4")+" value="+value+" OK");
        else {
            if(result.Length!=56+4*value||U32(result,44)!=address||U32(result,48)!=value)throw new IOException("Read response range mismatch");
            string values="";for(int i=0;i<value;i++)values+=" "+U32(result,52+i*4).ToString("X8");
            Event("READ seq="+sequence+" addr="+address.ToString("X4")+" values="+values);
        }
        return result;
    }
    void Diagnostic(byte req,string suffix) {
        CyControlEndPoint e=device.ControlEndPt;e.Target=CyConst.TGT_DEVICE;e.ReqType=CyConst.REQ_VENDOR;
        e.Direction=CyConst.DIR_FROM_DEVICE;e.ReqCode=req;e.Value=0;e.Index=0;e.TimeOut=1000;
        byte[] b=new byte[32];int n=32;
        if(!e.XferData(ref b,ref n)||n!=32)throw new IOException("EP0 diagnostic failed");
        File.WriteAllBytes(Path.Combine(directory,"b"+(req-0xb0)+"_"+suffix+".bin"),b);
        if(req==0xb1&&U32(b,0)!=0x31305047)throw new IOException("Wrong firmware");
        Event("DIAG "+req.ToString("X2")+" "+BitConverter.ToString(b));
    }
    int Run(string target,string plan) {
        string[] lines=File.ReadAllLines(plan);
        foreach(string line in lines)if(line.Trim().Length>0&&!line.Trim().StartsWith("#"))Validate(line.Split(new[]{' ','\t'},StringSplitOptions.RemoveEmptyEntries));
        directory=Path.GetFullPath(target);if(Directory.Exists(directory))throw new IOException("Capture exists");Directory.CreateDirectory(directory);
        File.Copy(plan,Path.Combine(directory,"plan.txt"));
        log=new StreamWriter(Path.Combine(directory,"run.log"));raw=new FileStream(Path.Combine(directory,"bulk_in.bin"),FileMode.CreateNew);
        int result=0;
        try {
            devices=new USBDeviceList(CyConst.DEVICES_CYUSB);int matches=0;
            foreach(USBDevice d in devices){CyUSBDevice c=d as CyUSBDevice;if(c!=null&&c.VendorID==0x04b4&&c.ProductID==0x00f1){device=c;matches++;}}
            if(matches!=1)throw new IOException("Expected exactly one 04B4:00F1; found "+matches);
            input=device.EndPointOf(0x86) as CyBulkEndPoint;output=device.EndPointOf(0x02) as CyBulkEndPoint;
            if(input==null||output==null)throw new IOException("Endpoints missing");input.TimeOut=250;output.TimeOut=1000;
            Diagnostic(0xb1,"before");Diagnostic(0xb0,"before");Drain(1500);
            foreach(string line in lines) {
                if(line.Trim().Length==0||line.Trim().StartsWith("#"))continue;
                string[] f=line.Split(new[]{' ','\t'},StringSplitOptions.RemoveEmptyEntries);
                if(f[0]=="WAIT"){Event(line);Drain((int)Number(f[1])*1000);}else Command(f[0]=="W",Number(f[1]),Number(f[2]));
            }
        } catch(Exception e){result=1;Event("ERROR "+e.Message);}
        finally {
            uint[] restore=new uint[touched.Count];touched.CopyTo(restore);
            foreach(uint address in restore)try{Command(true,address,0);}catch(Exception e){result=1;Event("CLEANUP_FAILED "+address.ToString("X4")+" "+e.Message);}
            if(input!=null)try{Drain(2500);Diagnostic(0xb0,"after");Diagnostic(0xb1,"after");}catch(Exception e){result=1;Event("FINAL_DIAG_FAILED "+e.Message);}
            Event("FINISHED frames="+frames+" bytes="+bytes+" empty_waits="+timeouts+" trailing="+pending.Count+" exit="+result);
            raw.Dispose();log.Dispose();if(devices!=null)devices.Dispose();
        }
        return result;
    }
    [STAThread]static int Main(string[] args){try{if(args.Length!=2)throw new Exception("Usage: SensorRun.exe NEW_CAPTURE_DIRECTORY PLAN_FILE");return new SensorRun().Run(args[0],args[1]);}catch(Exception e){Console.Error.WriteLine(e);return 2;}}
}
