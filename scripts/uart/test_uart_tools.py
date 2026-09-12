from __future__ import annotations

import io
import unittest
from unittest import mock

import capture_uart
from sanitize_uart import sanitize_text


class SanitizerTests(unittest.TestCase):
    def test_redacts_device_secrets(self) -> None:
        source = (
            "MAC=00:11:22:33:44:55 serial number: GAPD1234 "
            "password=hunter2 public=8.8.8.8 lan=192.168.219.1"
        )
        result = sanitize_text(source)
        self.assertNotIn("00:11:22:33:44:55", result)
        self.assertNotIn("GAPD1234", result)
        self.assertNotIn("hunter2", result)
        self.assertNotIn("8.8.8.8", result)
        self.assertIn("192.168.219.1", result)

    def test_redacts_url_credentials_and_secret_query(self) -> None:
        result = sanitize_text("https://alice:pw@example.test/fw?token=abc&version=1")
        self.assertNotIn("alice", result)
        self.assertNotIn("abc", result)
        self.assertIn("version=1", result)


class SinkTests(unittest.TestCase):
    @mock.patch.object(capture_uart, "local_timestamp", return_value="TIME")
    def test_timestamps_complete_and_partial_lines(self, _timestamp) -> None:
        output = io.StringIO()
        sink = capture_uart.TimestampedTextSink(output, console=False)
        sink.feed(b"one\r\ntwo")
        sink.finish()
        self.assertEqual(output.getvalue(), "TIME one\nTIME two\n")


class ReceiveOnlyTests(unittest.TestCase):
    def test_explicit_transmit_methods_are_blocked(self) -> None:
        receiver = capture_uart.ReceiveOnlySerial(port=None)
        with self.assertRaises(RuntimeError):
            receiver.write(b"x")
        with self.assertRaises(RuntimeError):
            receiver.writelines([b"x"])
        with self.assertRaises(RuntimeError):
            receiver.send_break()
        with self.assertRaises(RuntimeError):
            receiver.break_condition = True


if __name__ == "__main__":
    unittest.main()
