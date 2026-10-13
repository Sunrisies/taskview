#!/usr/bin/env python3
"""采样现有 TaskView 进程的 RSS 和累计 CPU 时间；不启动应用、不触发截图。"""
import argparse
import csv
from datetime import datetime
from pathlib import Path
import subprocess
import time


def seconds(value: str) -> float:
    """解析 ps 的 [[天-]时:]分:秒时间格式。"""
    days, clock = (value.split('-', 1) if '-' in value else ('0', value))
    parts = clock.split(':')
    if len(parts) not in (2, 3):
        raise ValueError(f'无法解析时间：{value}')
    total = 0.0
    for part in parts:
        total = total * 60 + float(part)
    return float(days) * 86400 + total


def read_process(pid: int) -> dict:
    """读取一份进程快照；RSS 的单位是 KiB，CPU 时间为进程累计消耗。"""
    result = subprocess.run(['/bin/ps', '-p', str(pid), '-o', 'pid=,rss=,time=,etime='],
                            text=True, capture_output=True, check=False)
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(result.stderr.strip() or '进程已退出或不可访问')
    fields = result.stdout.split()
    if len(fields) != 4:
        raise RuntimeError(f'无法解析进程统计：{result.stdout.strip()}')
    return {'pid': int(fields[0]), 'rss_mib': int(fields[1]) / 1024,
            'cpu_seconds': seconds(fields[2]), 'process_age_seconds': seconds(fields[3])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, help='指定 TaskView 进程 PID；默认自动查找')
    parser.add_argument('--duration', type=float, default=60, help='采样秒数，默认 60；最长 86400')
    parser.add_argument('--interval', type=float, default=5, help='采样间隔秒数，默认 5')
    parser.add_argument('--output', type=Path, help='CSV 保存路径')
    args = parser.parse_args()
    if not 0 < args.duration <= 86400 or args.interval <= 0 or (args.pid is not None and args.pid <= 0):
        parser.error('时长须在 0～86400 秒之间，间隔和 PID 须为正数')
    pid = args.pid
    if pid is None:
        result = subprocess.run(['/usr/bin/pgrep', '-x', 'TaskView'], text=True, capture_output=True)
        ids = result.stdout.split()
        if len(ids) != 1:
            parser.exit(1, '请先启动 TaskView；多个实例或自动查找失败时，用 --pid 指定进程。\n' + result.stderr)
        pid = int(ids[0])
    output = args.output or Path(__file__).resolve().parents[1] / 'build' / 'performance' / (
        'idle-' + datetime.now().strftime('%Y%m%d-%H%M%S') + '.csv')
    samples = []
    started = time.monotonic()
    # 每份采样立即写入 CSV，即使用户中断，也保留已经取得的数据。
    try:
        first = read_process(pid)
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open('w', newline='', encoding='utf-8') as stream:
            writer = csv.DictWriter(stream, fieldnames=['elapsed_seconds', *first.keys()])
            writer.writeheader()
            while True:
                sample = first if not samples else read_process(pid)
                elapsed = time.monotonic() - started
                sample['elapsed_seconds'] = elapsed
                samples.append(sample)
                writer.writerow(sample)
                stream.flush()
                print(f'{elapsed:7.1f}s  RSS={sample["rss_mib"]:.2f} MiB  累计 CPU={sample["cpu_seconds"]:.2f}s', flush=True)
                remaining = args.duration - elapsed
                if remaining <= 0:
                    break
                time.sleep(min(args.interval, remaining))
    except (RuntimeError, OSError) as error:
        parser.exit(1, f'无法采样：{error}\n')
    except KeyboardInterrupt:
        print('\n采样已中断，保留已有结果。')
    if len(samples) >= 2:
        span = samples[-1]['elapsed_seconds'] - samples[0]['elapsed_seconds']
        cpu = samples[-1]['cpu_seconds'] - samples[0]['cpu_seconds']
        memory = [sample['rss_mib'] for sample in samples]
        print(f'区间平均 CPU：{cpu / span * 100:.3f}%（一个核心为 100%）')
        print(f'RSS 起始/结束/峰值：{memory[0]:.2f} / {memory[-1]:.2f} / {max(memory):.2f} MiB')
    print(f'CSV：{output}')


if __name__ == '__main__':
    main()
