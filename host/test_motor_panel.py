import unittest
from motor_panel import Motor, Cancelled


class FakeUsb:
    def __init__(self):
        self.writes = []
        self.system = [0x00010101, 0, 0, 9]
        self.motor = [0x00470200, 0, 2, 0, 40, 100, 500000, 1000000,
                      0, 0, 0, 0, 4, 0, 0, 0, 100000000, 2000, 400]
        self.fail_move_ack = False
        self.on_write = lambda address, value: None

    def read(self, address, count=1):
        if address == 0:
            return self.system[:count]
        if address == 0x1000:
            return [0x00020200]
        if 0x6700 <= address <= 0x6748:
            start = (address - 0x6700) // 4
            return self.motor[start:start + count]
        return [0] * count

    def write(self, address, value):
        self.writes.append((address, value))
        if address == 4:
            self.system[1] = value
        elif address == 0x6704:
            self.motor[1] = value
            self.motor[15] = (self.motor[15] & ~3) | value
        elif address == 0x6710:
            self.motor[4] = value & 0xffffffff
        elif address == 0x6714:
            self.motor[5] = value
            self.motor[6] = (100000000 + 2 * value - 1) // (2 * value)
        elif address == 0x6738:
            self.motor[15] |= 32
        elif address == 0x672c:
            steps = self.motor[4]
            signed = steps if steps < 0x80000000 else steps - 0x100000000
            self.motor[9] = (self.motor[9] + signed) & 0xffffffff
            self.motor[13] += 1
            self.motor[15] = 37 | (abs(signed) << 8)
            if self.fail_move_ack:
                raise TimeoutError('MOVE accepted but ACK lost')
        self.on_write(address, value)

    def close(self):
        pass


class MotorTest(unittest.TestCase):
    def setUp(self):
        self.usb = FakeUsb()
        self.motor = Motor(self.usb)

    def test_status_has_no_writes(self):
        self.motor.status()
        self.assertEqual(self.usb.writes, [])

    def test_forward_reverse_and_boundaries_release(self):
        for steps, hz in ((40, 100), (-5000, 20), (5000, 400), (1, 400), (-1, 137)):
            with self.subTest(steps=steps, hz=hz):
                usb = FakeUsb()
                Motor(usb).move(steps, hz)
                self.assertEqual(usb.writes.count((0x672c, 1)), 1)
                self.assertEqual(usb.motor[9], steps & 0xffffffff)
                self.assertEqual(usb.motor[1], 0)
                self.assertEqual(usb.system[1], 0)

    def test_bad_parameters_send_nothing(self):
        for steps, hz in ((0, 100), (5001, 100), (-5001, 100), (40, 19), (40, 401)):
            with self.assertRaises(RuntimeError):
                self.motor.move(steps, hz)
        self.assertEqual(self.usb.writes, [])

    def test_wrong_firmware_or_active_other_module_blocks_move(self):
        self.usb.motor[0] = 0
        with self.assertRaises(RuntimeError):
            self.motor.move(40, 100)
        self.assertEqual(self.usb.writes, [])
        self.usb.motor[0] = 0x00470200
        original = self.usb.read
        self.usb.read = lambda a, count=1: [1] if a == 0x6804 else original(a, count)
        with self.assertRaises(RuntimeError):
            self.motor.move(40, 100)
        self.assertEqual(self.usb.writes, [])

    def test_lost_move_ack_never_retries_and_disables(self):
        self.usb.fail_move_ack = True
        with self.assertRaises(TimeoutError):
            self.motor.move(40, 100)
        self.assertEqual(self.usb.writes.count((0x672c, 1)), 1)
        self.assertEqual(self.usb.writes[-2:], [(0x6704, 0), (4, 0)])

    def test_stop_during_setup_prevents_move_and_disables(self):
        self.usb.on_write = lambda a, v: self.motor.cancel.set() if a == 0x6710 else None
        with self.assertRaises(Cancelled):
            self.motor.move(40, 100)
        self.assertNotIn((0x672c, 1), self.usb.writes)
        self.assertEqual(self.usb.writes[-2:], [(0x6704, 0), (4, 0)])

    def test_stop_after_move_prevents_further_heartbeat(self):
        self.usb.on_write = lambda a, v: self.motor.cancel.set() if a == 0x672c else None
        with self.assertRaises(Cancelled):
            self.motor.move(40, 100)
        move_index = self.usb.writes.index((0x672c, 1))
        self.assertEqual(self.usb.writes[move_index + 1:], [(0x6704, 0), (4, 0)])

    def test_stalled_ui_does_not_move(self):
        self.motor.ui_alive -= 5
        with self.assertRaises(RuntimeError):
            self.motor.move(40, 100)
        self.assertEqual(self.usb.writes, [])

    def test_disconnect_cleanup_is_not_reported_as_success(self):
        self.usb.write = lambda a, v: (_ for _ in ()).throw(IOError('disconnected'))
        with self.assertRaisesRegex(RuntimeError, '禁用确认失败'):
            self.motor.release(global_off=True)


if __name__ == '__main__':
    unittest.main()
