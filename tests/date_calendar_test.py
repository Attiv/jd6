import datetime
import pathlib
import random
import shutil
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class CivilCalendarTests(unittest.TestCase):
    def test_calendar_matches_python_for_boundaries_and_seeded_samples(self):
        values = [1, 59, 60, 365, 366, 693655, 730179, 3652059]
        rng = random.Random(42)
        values += [rng.randint(1, 3652059) for _ in range(500)]
        script = "package.path='./lua/?.lua;'..package.path; local m=require('xmjd6.date_tools'); "
        script += 'for _,n in ipairs({' + ','.join(map(str, values)) + '}) do '
        script += "local s=assert(m.from_serial(n)); print(s); assert(m.parse(s:gsub('%-','')).serial==n) end"
        output = subprocess.check_output([shutil.which('lua5.4') or shutil.which('lua'), '-'],
                                         input=script, text=True, cwd=ROOT)
        self.assertEqual(output.splitlines(), [datetime.date.fromordinal(n).isoformat() for n in values])


if __name__ == '__main__':
    unittest.main()
