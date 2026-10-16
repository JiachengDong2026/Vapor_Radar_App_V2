"""Independent transfer-function checks for all quantized low-pass profiles."""
import unittest
from pathlib import Path
import numpy as np
from generate_lpf_coefficients import CUTOFFS, coefficients, generate


class FilterProfiles(unittest.TestCase):
    def test_quantized_response(self):
        for rate in (1000000, 12500000):
            for cutoff in CUTOFFS:
                response = 1+0j
                for section in (0, 1):
                    b0, b1, a1, a2 = coefficients(rate, cutoff, section)
                    scale = 2**46
                    self.assertEqual(2*b0+b1, scale+a1+a2)
                    self.assertTrue(np.all(np.abs(np.roots([1, a1/scale, a2/scale])) < 1))
                    z = np.exp(-2j*np.pi*cutoff/rate)
                    response *= (b0+b1*z+b0*z*z)/(scale+a1*z+a2*z*z)
                self.assertAlmostEqual(20*np.log10(abs(response)), -3.0102999566, delta=0.001)

    def test_checked_in_coefficients(self):
        actual = Path(__file__).resolve().parents[1]/'rtl/dila/dila_lpf_coefficients.v'
        self.assertEqual(actual.read_text(encoding='utf-8'), generate())


if __name__ == '__main__':
    unittest.main()
