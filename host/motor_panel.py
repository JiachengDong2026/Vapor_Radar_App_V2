"""Small manual DM422 panel. No image loading and no motion on startup."""
import argparse
import json
import os
from pathlib import Path
import queue
import threading
import time
import tkinter as tk
from tkinter import filedialog, ttk

from gnss_motor_control import Usb


OTHER_CONTROLS = (0x2004, 0x2104, 0x3004, 0x3104, 0x4004, 0x4104,
                  0x5004, 0x5104, 0x6004, 0x6104, 0x6204, 0x6304,
                  0x6404, 0x6504, 0x6604, 0x6804, 0x6904)


class Cancelled(Exception):
    pass


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


class Motor:
    """Only the worker owns USB. UI cancellation is a thread-safe event."""
    def __init__(self, usb, log=lambda message: None):
        self.usb = usb
        self.log = log
        self.cancel = threading.Event()
        self.ui_alive = time.monotonic()
        self.last_heartbeat = 0
        self.max_gap = 0
        self.active = False

    def status(self):
        system = self.usb.read(0, 4)
        require(self.usb.read(0x1000)[0] == 0x00020200, 'TIME 固件版本不匹配')
        motor = self.usb.read(0x6700, 19)
        require(motor[0] == 0x00470200, 'MOTOR 固件版本不匹配，请加载整机比特流')
        return system, motor

    def guard(self):
        if self.cancel.is_set():
            raise Cancelled('用户停止，已取消后续运动操作')
        require(time.monotonic() - self.ui_alive < 1.0, '窗口响应中断，停止发送心跳')

    def write(self, address, value):
        self.guard()
        self.usb.write(address, value)

    def heartbeat(self):
        self.guard()
        now = time.monotonic()
        if self.last_heartbeat:
            self.max_gap = max(self.max_gap, now - self.last_heartbeat)
        self.usb.write(0x6738, 1)
        self.last_heartbeat = now

    def release(self, global_off=False):
        # Attempt both shutdown writes even if one ACK is missing. Never MOVE here.
        errors = []
        for address in ((0x6704, 4) if global_off else (0x6704,)):
            try:
                self.usb.write(address, 0)
            except Exception as exc:
                errors.append(str(exc))
        try:
            system, motor = self.status()
            require(motor[1] == 0 and motor[15] & 3 == 0, '电机禁用尚未确认')
            require(not global_off or system[1] == 0, '全局关闭尚未确认')
        except Exception as exc:
            errors.append(str(exc))
        require(not errors, '禁用确认失败；检查现场电源：' + '; '.join(errors))
        self.log('已确认电机禁用、空闲' + ('，全局控制关闭' if global_off else ''))
        return system, motor

    def move(self, steps, hz):
        require(type(steps) is int and 1 <= abs(steps) <= 400, '脉冲数须为 1～400')
        require(type(hz) is int and 20 <= hz <= 400, '频率须为 20～400 Hz')
        self.guard()
        system, initial = self.status()
        require(system[1] == 0, '全局控制已启用，请先停止其他控制程序')
        require(initial[1] == 0 and initial[2] & 0x4b == 2 and initial[15] & 3 == 0,
                '电机不是禁用空闲状态，请先点击停止 / 禁用')
        require(initial[3] == 0 and initial[15] & 0x18 == 0,
                '电机有错误；先禁用并检查，再使用清除错误')
        require((initial[12], initial[16], initial[17], initial[18]) ==
                (4, 100000000, 2000, 400), '电机极性或时序配置不匹配')
        for address in OTHER_CONTROLS:
            self.guard()
            require(self.usb.read(address)[0] == 0, f'其他模块 {address:04X} 正在启用')
        touched = False
        self.last_heartbeat = 0
        self.max_gap = 0
        try:
            touched = True
            self.write(0x6704, 0)
            self.write(0x6714, hz)
            self.write(0x6710, steps)
            configured = self.usb.read(0x6710, 3)
            half_period = (100000000 + 2 * hz - 1) // (2 * hz)
            require(configured[0] == steps & 0xffffffff and configured[2] == half_period,
                    '运动参数读回不匹配')
            self.heartbeat()
            self.write(4, 1)
            self.heartbeat()
            self.write(0x6704, 1)
            self.heartbeat()
            require(self.usb.read(0x673c)[0] & 0x3b == 0x21, '使能状态异常')
            self.heartbeat()
            self.log(f'发送一次运动：{steps:+d} 脉冲，{hz} Hz')
            self.write(0x672c, 1)  # Never retry, even if its ACK is lost.
            deadline = time.monotonic() + abs(steps) / hz + 5
            while True:
                self.heartbeat()
                core = self.usb.read(0x673c)[0]
                require(core & 0x18 == 0, '电机看门狗或参数错误')
                if not core & 2:
                    require(core & 4, '运动结束但未报告完成')
                    break
                require(time.monotonic() < deadline, '运动等待超时')
                self.cancel.wait(0.02)
            self.heartbeat()
            final = self.usb.read(0x6700, 19)
            require(final[3] == 0 and final[10] == 0 and
                    (final[15] >> 8) & 0xffff == abs(steps) and
                    (final[9] - initial[9]) & 0xffffffff == steps & 0xffffffff and
                    (final[13] - initial[13]) & 0xffffffff == 1,
                    '运动计数核验失败')
            self.log(f'FPGA 已完成 {abs(steps)} 脉冲；实际位移请现场观察')
        finally:
            if touched:
                self.release(global_off=True)
            self.log(f'本次最大心跳发送间隔 {self.max_gap:.3f}s（目标 ≤0.250s）')

    def clear_error(self):
        _, motor = self.status()
        require(motor[1] == 0 and motor[15] & 3 == 0, '先禁用电机再清除错误')
        self.usb.write(0x6704, 0)
        self.usb.write(0x670c, 0xffffffff)
        self.log('已发送清除电机错误；保留软件位置计数')
        return self.status()


class Panel:
    def __init__(self, root, bridge):
        self.root = root
        self.motor = None
        self.busy = False
        self.closing = False
        self.events = queue.Queue()
        logdir = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'VaporMotorPanel' / 'logs'
        logdir.mkdir(parents=True, exist_ok=True)
        self.logfile = (logdir / (time.strftime('%Y%m%d_%H%M%S') + f'_{os.getpid()}.log')).open('a', encoding='utf-8')
        root.title('DM422 电机测试')
        root.geometry('780x630')
        root.minsize(720, 580)
        root.protocol('WM_DELETE_WINDOW', self.close)
        frame = ttk.Frame(root, padding=18)
        frame.pack(fill='both', expand=True)
        ttk.Label(frame, text='DM422 手动测试', font=('Microsoft YaHei UI', 18, 'bold')).pack(anchor='w')
        ttk.Label(frame, text='45°反射镜：上移接入光路，下移移出光路。每次点动完成后自动禁用。').pack(anchor='w', pady=(5, 12))
        self.bridge = tk.StringVar(value=str(bridge))
        row = ttk.Frame(frame); row.pack(fill='x')
        ttk.Entry(row, textvariable=self.bridge).pack(side='left', fill='x', expand=True)
        self.browse = ttk.Button(row, text='选择桥接程序', command=self.choose)
        self.browse.pack(side='left', padx=(8, 0))
        row = ttk.Frame(frame); row.pack(fill='x', pady=10)
        self.connect_button = ttk.Button(row, text='连接 / 检查', command=lambda: self.run('connect'))
        self.connect_button.pack(side='left')
        self.refresh_button = ttk.Button(row, text='刷新状态', command=lambda: self.run('status'))
        self.refresh_button.pack(side='left', padx=8)
        self.clear_button = ttk.Button(row, text='清除电机错误', command=lambda: self.run('clear'))
        self.clear_button.pack(side='left')
        self.state = tk.StringVar(value='未连接；不会自动下载或运动')
        ttk.Label(frame, textvariable=self.state, wraplength=720, font=('Microsoft YaHei UI', 10)).pack(anchor='w', pady=6)
        box = ttk.LabelFrame(frame, text='点动参数', padding=12); box.pack(fill='x', pady=8)
        self.steps = tk.StringVar(value='40'); self.hz = tk.StringVar(value='100')
        ttk.Label(box, text='脉冲数（1～400）').grid(row=0, column=0, sticky='w')
        ttk.Spinbox(box, from_=1, to=400, textvariable=self.steps, width=9).grid(row=0, column=1, padx=8)
        ttk.Label(box, text='频率（20～400 Hz）').grid(row=0, column=2)
        ttk.Spinbox(box, from_=20, to=400, textvariable=self.hz, width=9).grid(row=0, column=3, padx=8)
        ttk.Button(box, text='40 脉冲', command=lambda: self.steps.set('40')).grid(row=1, column=0, pady=8)
        ttk.Button(box, text='400 脉冲', command=lambda: self.steps.set('400')).grid(row=1, column=1)
        ttk.Label(box, text='400 脉冲 ≈ 1mm，仅在 1600 脉冲/转、4mm 导程时成立。').grid(row=2, column=0, columnspan=4, sticky='w')
        row = ttk.Frame(frame); row.pack(fill='x', pady=8)
        self.forward = ttk.Button(row, text='上移 ＋（接入方向）', command=lambda: self.start_move(1))
        self.forward.pack(side='left', expand=True, fill='x')
        self.reverse = ttk.Button(row, text='下移 −（移出方向）', command=lambda: self.start_move(-1))
        self.reverse.pack(side='left', expand=True, fill='x', padx=8)
        self.stop = tk.Button(row, text='停止 / 禁用', bg='#b42318', fg='white', command=self.stop_now)
        self.stop.pack(side='left', expand=True, fill='x')
        ttk.Label(frame, text='停止通过 USB 下发，可能有通信延迟；不代替硬件急停。计数是 FPGA 输出脉冲，不是位置反馈。', wraplength=720).pack(anchor='w')
        self.output = tk.Text(frame, height=10, state='disabled', wrap='word')
        self.output.pack(fill='both', expand=True, pady=(12, 0))
        self.show('日志：' + str(self.logfile.name))
        self.controls()
        root.after(50, self.pump)

    def choose(self):
        value = filedialog.askopenfilename(filetypes=[('USB bridge', '*.exe')])
        if value:
            self.bridge.set(value)

    def show(self, message):
        line = time.strftime('%H:%M:%S ') + message + '\n'
        self.logfile.write(line); self.logfile.flush()
        self.output.configure(state='normal'); self.output.insert('end', line)
        self.output.see('end'); self.output.configure(state='disabled')

    def controls(self):
        connected = self.motor is not None
        for button in (self.forward, self.reverse, self.refresh_button, self.clear_button):
            button.configure(state='normal' if connected and not self.busy and not self.closing else 'disabled')
        for button in (self.connect_button, self.browse):
            button.configure(state='normal' if not self.busy and not self.closing else 'disabled')
        self.stop.configure(state='normal' if connected and not self.closing else 'disabled')

    def start_move(self, sign):
        try:
            steps, hz = int(self.steps.get()), int(self.hz.get())
            require(1 <= steps <= 400 and 20 <= hz <= 400, '脉冲数 1～400，频率 20～400 Hz')
        except (ValueError, RuntimeError) as exc:
            self.show('参数错误：' + str(exc)); return
        self.run('move', sign * steps, hz)

    def run(self, action, *args):
        if self.busy or self.closing:
            return
        self.busy = True
        self.state.set('正在连接…' if action == 'connect' else '正在执行：' + action)
        if self.motor:
            self.motor.cancel.clear()
        bridge = self.bridge.get()
        self.controls()
        def worker():
            try:
                if action == 'connect':
                    if self.motor:
                        self.motor.usb.close(); self.motor = None
                    require(Path(bridge).is_file(), '找不到 VaporUsbBridge.exe')
                    candidate = Motor(Usb(bridge), lambda text: self.events.put(('log', text)))
                    try:
                        status = candidate.status()
                    except Exception:
                        candidate.usb.close(); raise
                    self.motor = candidate
                elif action == 'move':
                    self.motor.move(*args)
                    status = self.motor.status()
                elif action == 'release':
                    status = self.motor.release()
                elif action == 'clear':
                    status = self.motor.clear_error()
                else:
                    status = self.motor.status()
                self.events.put(('status', status))
            except Exception as exc:
                self.events.put(('error', str(exc)))
                # Reconnection is explicit. Never queue/replay a motion.
                if self.motor:
                    try:
                        self.motor.usb.close()
                    except Exception:
                        pass
                    self.motor = None
            finally:
                self.events.put(('done', None))
        threading.Thread(target=worker, daemon=True).start()

    def stop_now(self):
        if self.motor:
            self.motor.cancel.set()
        if not self.busy:
            self.run('release')
        self.show('已请求停止 / 禁用，等待 USB 确认')

    def pump(self):
        if self.motor:
            self.motor.ui_alive = time.monotonic()
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == 'log':
                self.show(value)
            elif kind == 'error':
                self.show('错误：' + value)
                self.state.set('操作失败；状态未确认。检查日志，重新连接后再操作。')
            elif kind == 'status':
                system, motor = value
                position = motor[9] if motor[9] < 0x80000000 else motor[9] - 0x100000000
                self.state.set(f"电机 {'忙' if motor[15] & 2 else '空闲'} / {'使能' if motor[15] & 1 else '禁用'}　"
                               f'累计脉冲 {position}　剩余 {motor[10]}　运动编号 {motor[13]}\n'
                               f'电机错误 0x{motor[3]:08X}　系统错误 0x{system[3]:08X}')
                self.show('状态 ' + json.dumps({'system': system, 'motor': motor}))
            elif kind == 'done':
                self.busy = False
                self.controls()
        if self.closing and not self.busy:
            if self.motor:
                # Only close after the release worker completes.
                self.motor.usb.close(); self.motor = None
            self.logfile.close(); self.root.destroy(); return
        self.root.after(50, self.pump)

    def close(self):
        if self.closing:
            return
        if self.motor:
            self.stop_now()
        self.closing = True
        self.controls()


def default_bridge():
    local = Path(__file__).resolve().parent / 'VaporUsbBridge.exe'
    if local.exists():
        return local
    return Path('E:/Documents/Vapor_Lc_App_Test/qt_formal_sync_20261011/dist/VaporUsbBridge.exe')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge', type=Path, default=default_bridge())
    parser.add_argument('--check', action='store_true', help='Read-only hardware check; no enable or motion')
    args = parser.parse_args()
    if args.check:
        usb = Usb(args.bridge)
        try:
            system, motor = Motor(usb).status()
            print(json.dumps({'system': system, 'motor': motor}))
        finally:
            usb.close()
        return
    root = tk.Tk()
    Panel(root, args.bridge)
    root.mainloop()


if __name__ == '__main__':
    main()
