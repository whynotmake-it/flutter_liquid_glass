#!/usr/bin/env python3
"""The grid bench from the Mac: flat against glass, one table per run.

    grid.py build                   builds the APK (profile mode)
    grid.py run <name> [key=v...]   runs it, prints glass against flat and the goal
    grid.py show <name>             prints a finished run again
    grid.py report <file.json>      reads what a device check sent

Keys are those of lib/perf/grid_bench.dart. A run writes
<out>/<name>/result.json. Set ANDROID_SERIAL for another phone than the Pixel
6a; rails and Mali counters exist only where the phone offers them, and the
table leaves those columns empty elsewhere.

A change counts when the 95% interval of the pair differences leaves zero. A
run with an error in the app, or whose arms drew a different number of frames,
is marked INVALID whatever its numbers say.
"""
import base64
import json
import math
import os
import re
import subprocess
import sys

os.environ.setdefault('AB_SKIP_S', '0.2')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ab_energy  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLE = os.path.dirname(os.path.dirname(HERE))
APK = os.environ.get(
    'GRID_APK', f'{EXAMPLE}/build/app/outputs/flutter-apk/app-profile.apk')
OUT = os.environ.get('GRID_OUT', '/tmp/morph-grid')
FLUTTER = os.environ.get('FLUTTER', 'flutter')
GOAL = {'frag stage ms/frame': 1.0, 'build_ms': 0.5}
# An Android property holds 91 characters.
PROP = 91


def build():
    subprocess.run([FLUTTER, 'build', 'apk', '--profile', '-t',
                    'lib/perf/grid_bench.dart'], cwd=EXAMPLE, check=True)


def set_config(config):
    parts, first = config.split(';'), []
    while parts and len(';'.join(first + parts[:1])) <= PROP:
        first.append(parts.pop(0))
    rest = ';'.join(parts) or 'x=0'
    if len(rest) > PROP:
        sys.exit(f'config too long: {config}')
    for name, value in (('cfg', ';'.join(first)), ('cfg2', rest)):
        ab_energy.adb('shell', 'setprop', f'debug.grid.{name}', f"'{value}'")


def stats(diffs):
    n = len(diffs)
    if n < 2:
        return None
    mean = sum(diffs) / n
    sd = math.sqrt(sum((d - mean) ** 2 for d in diffs) / (n - 1))
    return {'mean': mean, 'ci': 2 * sd / math.sqrt(n), 'n': n}


def counters(out):
    names, rails, work, freq, ticks, windows, mali = ab_energy.load(out)
    by_cell = {}
    for w in windows:
        by_cell.setdefault(w['step'], []).append(w)
    result = {}
    for cell, ws in by_cell.items():
        ms = [(w['arm'], ab_energy.measure(names, rails, work, freq, ticks, w,
                                           mali)) for w in ws]
        pairs = []
        for i in range(0, len(ms) - 1, 2):
            (x, mx), (y, my) = ms[i], ms[i + 1]
            if {x, y} == {'A', 'B'}:
                pairs.append((mx, my) if x == 'A' else (my, mx))
        keys = ('frag stage ms/frame', 'total mW', 'passes/frame')
        result[cell] = {}
        for key in keys:
            present = [(a[key], b[key]) for a, b in pairs
                       if key in a and key in b]
            if present:
                result[cell][key] = {
                    'a': sum(a for a, _ in present) / len(present),
                    'b': sum(b for _, b in present) / len(present),
                    **(stats([b - a for a, b in present]) or {}),
                }
    return result


def collect(name):
    out = f'{OUT}/{name}'
    log = open(f'{out}/log.txt').read()
    run = re.search(r'GRID_RUN (\{.*)', log)
    if not run:
        tail = log[-800:]
        sys.exit(f'the app wrote no report:\n{tail}')
    result = json.loads(run.group(1))
    result['cells'] = [json.loads(x)
                       for x in re.findall(r'GRID_CELL (\{.*)', log)]
    gpu = counters(out)
    invalid = []
    if result['errors']:
        invalid.append(f"{result['errors']} errors in the app")
    if 'GRID_FAILED' in log or 'Unhandled Exception' in log:
        invalid.append('the app failed')
    for cell in result['cells']:
        cell['counters'] = gpu.get(cell['cell'], {})
        a, b = cell['frames_a'], cell['frames_b']
        if max(a, b) and min(a, b) < 0.9 * max(a, b):
            invalid.append(f"{cell['cell']}: frames {a} against {b}")
    result['invalid'] = invalid
    json.dump(result, open(f'{out}/result.json', 'w'), indent=1)
    return result


def fmt(value, width=6, sign=False):
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return ' ' * (width - 1) + '-'
    return f'{value:+{width}.2f}' if sign else f'{value:{width}.2f}'


def mark(stat):
    if not stat or 'ci' not in stat:
        return ' '
    return '*' if abs(stat['mean']) > stat['ci'] else ' '


def table(result):
    print({k: result[k] for k in ('window_ms', 'pairs', 'seconds', 'refresh')})
    if result['invalid']:
        print('INVALID: ' + '; '.join(result['invalid']))
    print(f"{'cell':22} {'frames':>9} | {'ui A':>6} {'B-A':>6} |"
          f" {'raster A':>8} {'B-A':>6} | {'gpu A':>6} {'B-A':>6} {'+-':>5}"
          f"  | {'mW':>6} {'+-':>5}")
    for cell in result['cells']:
        c = cell['counters']
        gpu = c.get('frag stage ms/frame', {})
        mw = c.get('total mW', {})
        print(f"{cell['cell']:22} {cell['frames_a']:4}/{cell['frames_b']:<4} |"
              f" {fmt(cell['build_ms']['a'])} {fmt(cell['build_ms']['delta'], sign=True)} |"
              f"   {fmt(cell['raster_ms']['a'])} {fmt(cell['raster_ms']['delta'], sign=True)} |"
              f" {fmt(gpu.get('a'))} {fmt(gpu.get('mean'), sign=True)}{mark(gpu)}"
              f"{fmt(gpu.get('ci'), 5)} | {fmt(mw.get('mean'), sign=True)}{mark(mw)}"
              f"{fmt(mw.get('ci'), 5)}")


def goal_table(result):
    print('glass against flat, the goal is GPU +1 and UI +0.5 ms a frame')
    print(f"{'cell':22} {'GPU flat':>8} {'glass':>6} {'+':>6}     |"
          f" {'UI flat':>7} {'glass':>6} {'+':>6}     | {'raster +':>8}")
    for cell in result['cells']:
        if not cell['frames_a']:
            continue
        gpu = cell['counters'].get('frag stage ms/frame', {})
        ui = cell['build_ms']
        raster = cell['raster_ms']
        gpu_ok = gpu.get('mean') is not None and gpu['mean'] <= 1.0
        ui_ok = ui['delta'] is not None and ui['delta'] <= 0.5
        print(f"{cell['cell']:22} {fmt(gpu.get('a'), 8)} {fmt(gpu.get('b'))}"
              f" {fmt(gpu.get('mean'), sign=True)} {'ok ' if gpu_ok else 'NO '} |"
              f" {fmt(ui['a'], 7)} {fmt(ui['b'])} {fmt(ui['delta'], sign=True)}"
              f" {'ok ' if ui_ok else 'NO '} | {fmt(raster['delta'], 8, sign=True)}")


def report(path):
    data = json.load(open(path))
    if 'failed' in data:
        sys.exit(f"the check failed: {data['failed']}\n{data.get('stack', '')}")
    print(data['device'], data['os'])
    print('refresh', data['refresh'], 'screen', data['screen'],
          'errors', data['errors'])
    print('before', data['thermal_before'])
    print('after ', data['thermal_after'])
    print(f"{'cell':22} {'fps flat':>8} {'glass':>6} {'late %':>6} |"
          f" {'ui':>6} {'+':>6} | {'raster':>6} {'+':>6} | {'gpu~ +':>6} {'+-':>5}")

    def row(cell):
        fps, ui, raster = cell['fps'], cell['build_ms'], cell['raster_ms']
        proxy = cell.get('proxy') or {}
        print(f"{cell['cell']:22} {fmt(fps['a'], 8)} {fmt(fps['b'])}"
              f" {fmt(cell['late_pct']['b'])} |"
              f" {fmt(ui['a'])} {fmt(ui['delta'], sign=True)} |"
              f" {fmt(raster['a'])} {fmt(raster['delta'], sign=True)} |"
              f" {fmt(proxy.get('delta_ms'), sign=True)} {fmt(proxy.get('se_ms'), 5)}")

    for cell in data['cells']:
        row(cell)
        if 'snapshot' in cell:
            png = f"{os.path.splitext(path)[0]}_{cell['cell']}.png"
            open(png, 'wb').write(base64.b64decode(cell['snapshot']))
    print('warming up: t, fps, ui, raster, late %, thermal status, battery C')
    for step in data['sustained']:
        device = step.get('device') or {}
        print(f"{step['t']:4} {step['fps']:6.1f} {fmt(step['build_ms'])}"
              f" {fmt(step['raster_ms'])} {step['late_pct']:6.1f}"
              f" {device.get('status')} {device.get('battery_c')}")


def run(name, config):
    # A frame's cost depends on the orientation, and the phone may lie anyhow.
    ab_energy.adb('shell', 'settings', 'put', 'system',
                  'accelerometer_rotation', '0')
    ab_energy.adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
    set_config(config)
    out = f'{OUT}/{name}'
    subprocess.run(['rm', '-rf', out])
    ab_energy.run(APK, out)
    return collect(name)


if __name__ == '__main__':
    command = sys.argv[1]
    if command == 'build':
        build()
    elif command == 'run':
        result = run(sys.argv[2], ';'.join(sys.argv[3:]))
        table(result)
        goal_table(result)
    elif command == 'report':
        report(sys.argv[2])
    elif command == 'show':
        result = collect(sys.argv[2])
        table(result)
        goal_table(result)
