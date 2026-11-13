import struct
import unittest
import zlib
from decimal import Decimal
from gnss_motor_control import command_frame, utc_at_tick


class ControlTest(unittest.TestCase):
    def test_drift_corrected_utc_without_epoch_precision_loss(self):
        self.assertEqual(utc_at_tick(150150000,100100000,1700000000000000,100100000),
                         Decimal(1700000000500000))
        self.assertEqual(utc_at_tick(100099999,100100000,1700000000000000,100100000),
                         Decimal(1700000000000000)-Decimal(1000000)/Decimal(100100000))

    def test_reject_unknown_rate(self):
        with self.assertRaises(ValueError):utc_at_tick(1,0,0,0)

    def test_usb_read_and_signed_move_golden(self):
        read=command_frame(1,0x1048,count=7)
        self.assertEqual(struct.unpack_from('<II',read,40),(0x1048,7))
        self.assertEqual(len(read),52)
        write=command_frame(2,0x6710,-40)
        self.assertEqual(struct.unpack_from('<III',write,40),(0x6710,1,0xffffffd8))
        self.assertEqual(struct.unpack_from('<I',write,len(write)-4)[0],zlib.crc32(write[:-4]))


if __name__=='__main__':unittest.main()
