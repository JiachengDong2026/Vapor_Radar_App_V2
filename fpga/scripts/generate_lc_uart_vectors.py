"""Generate VLP commands and exact response payloads for dual LC UART loopback."""
import struct
import zlib
from pathlib import Path


def generate():
    output = Path(__file__).resolve().parents[1] / 'sim/system/vectors'
    commands, responses, sources = [], [], []

    def command(address, value=0, *, write=False, source=1, status=0):
        seq = len(responses) + 1
        payload = struct.pack('<II', address, 1)
        if write:
            payload += struct.pack('<I', value)
        header = struct.pack('<IBBBBI IHHI QII', 0x31504c56, 1, 0, 1, 10,
                             44 + len(payload), seq, source, 3 if write else 2,
                             0, 0, 0, len(payload))
        frame = header + payload
        frame += struct.pack('<I', zlib.crc32(frame))
        commands.extend(struct.unpack('<' + 'I' * (len(frame) // 4), frame))
        # WRITE_REG errors retain the standard 4-byte response; READ errors too.
        response = struct.pack('<I', status)
        if not write and not status:
            response += struct.pack('<III', address, 1, value)
        responses.append(response)
        sources.append(source)

    command(0x0004, 1, write=True)
    for index, base in enumerate((0x6800, 0x6900)):
        source = 0x48 + index
        command(base, (source << 16) | 0x100, source=source)
        command(base + 4, 0)
        command(base + 0x1c, status=11)
        command(base + 0x10, 1000000, write=True, source=source)
        command(base + 0x14, 0x108 if index == 0 else 0x218, write=True, source=source)
        command(base + 4, 1, write=True, source=source)
    for base, byte in ((0x6800, 0xa5), (0x6900, 0x3c), (0x6800, 0x5a), (0x6900, 0xc3)):
        command(base + 0x18, byte, write=True)
    phase_words, phase_responses = len(commands), len(responses)
    for index, base in enumerate((0x6800, 0x6900)):
        source = 0x48 + index
        command(base + 0x24, 2, source=source)
        command(base + 0x28, 2, source=source)
        command(base + 0x2c, 2, source=source)
        for byte in ((0xa5, 0x5a) if index == 0 else (0x3c, 0xc3)):
            command(base + 0x1c, byte, source=source)
        command(base + 0x1c, source=source, status=11)
        command(base, 0, write=True, source=source, status=6)
        command(base + 0x10, 9600, write=True, source=source, status=8)
        command(base, source=0x49 - index, status=4)
        command(base + 4, 2, write=True, source=source)
        command(base + 4, 0, source=source)
    (output / 'lc_top_commands.hex').write_text(''.join(f'{w:08x}\n' for w in commands))
    (output / 'lc_top_responses.hex').write_text(''.join(
        ''.join(f'{b:02x}\n' for b in p.ljust(64, b'\0')) for p in responses))
    (output / 'lc_top_response_lengths.hex').write_text(''.join(f'{len(p):02x}\n' for p in responses))
    (output / 'lc_top_response_sources.hex').write_text(''.join(f'{s:04x}\n' for s in sources))
    (output / 'lc_top_sizes.vh').write_text(
        f'localparam COMMAND_WORDS={len(commands)}, RESPONSES={len(responses)};\n'
        f'localparam PHASE_WORDS={phase_words}, PHASE_RESPONSES={phase_responses};\n')
    print(f'LC_VECTORS_GENERATED commands={len(responses)} words={len(commands)}')


if __name__ == '__main__':
    generate()
