#!/usr/bin/env python3
import argparse
import hashlib
import json
import plistlib
import struct
import zipfile
from pathlib import Path


def write_zip(path, files):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, text in sorted(files.items()):
            info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, text.encode('utf-8'))


def powerpoint(path):
    a = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    p = 'http://schemas.openxmlformats.org/presentationml/2006/main'
    r = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    def xml(text): return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + text
    def rels(items):
        return xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' + ''.join(
            '<Relationship Id="%s" Type="%s/%s" Target="%s"/>' % (i, r, kind, target) for i, kind, target in items) + '</Relationships>')
    tree = '<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree>'
    ns = 'xmlns:a="%s" xmlns:p="%s" xmlns:r="%s"' % (a, p, r)
    types = [('presentation', 'presentation.main'), ('slides/slide1', 'slide'), ('slideMasters/slideMaster1', 'slideMaster'), ('slideLayouts/slideLayout1', 'slideLayout'), ('theme/theme1', 'theme')]
    content = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
    content += ''.join('<Override PartName="/ppt/%s.xml" ContentType="application/vnd.openxmlformats-officedocument.%s+xml"/>' % (name, 'theme' if kind == 'theme' else 'presentationml.' + kind) for name, kind in types) + '</Types>'
    colors = [('dk1', '000000'), ('lt1', 'FFFFFF'), ('dk2', '1F497D'), ('lt2', 'EEECE1'), ('accent1', '4F81BD'), ('accent2', 'C0504D'), ('accent3', '9BBB59'), ('accent4', '8064A2'), ('accent5', '4BACC6'), ('accent6', 'F79646'), ('hlink', '0000FF'), ('folHlink', '800080')]
    theme = '<a:theme xmlns:a="%s" name="Blank"><a:themeElements><a:clrScheme name="Blank">' % a
    theme += ''.join('<a:%s><a:srgbClr val="%s"/></a:%s>' % (key, color, key) for key, color in colors) + '</a:clrScheme>'
    theme += '<a:fontScheme name="Blank">' + ''.join('<a:%s><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:%s>' % (kind, kind) for kind in ['majorFont', 'minorFont']) + '</a:fontScheme>'
    fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
    theme += '<a:fmtScheme name="Blank"><a:fillStyleLst>' + fill * 3 + '</a:fillStyleLst><a:lnStyleLst>'
    theme += ''.join('<a:ln w="%s">%s<a:prstDash val="solid"/></a:ln>' % (width, fill) for width in [6350, 12700, 19050])
    theme += '</a:lnStyleLst><a:effectStyleLst>' + '<a:effectStyle><a:effectLst/></a:effectStyle>' * 3 + '</a:effectStyleLst><a:bgFillStyleLst>' + fill * 3 + '</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>'
    files = {
        '[Content_Types].xml': xml(content),
        '_rels/.rels': rels([('rId1', 'officeDocument', 'ppt/presentation.xml')]),
        'ppt/presentation.xml': xml('<p:presentation %s><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst><p:sldId id="256" r:id="rId2"/></p:sldIdLst><p:sldSz cx="9144000" cy="6858000" type="screen4x3"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>' % ns),
        'ppt/_rels/presentation.xml.rels': rels([('rId1', 'slideMaster', 'slideMasters/slideMaster1.xml'), ('rId2', 'slide', 'slides/slide1.xml')]),
        'ppt/slides/slide1.xml': xml('<p:sld %s><p:cSld>%s</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (ns, tree)),
        'ppt/slides/_rels/slide1.xml.rels': rels([('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml')]),
        'ppt/slideLayouts/slideLayout1.xml': xml('<p:sldLayout %s type="blank" preserve="1"><p:cSld name="Blank">%s</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>' % (ns, tree)),
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels': rels([('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml')]),
        'ppt/slideMasters/slideMaster1.xml': xml('<p:sldMaster %s><p:cSld>%s</p:cSld><p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId2"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>' % (ns, tree)),
        'ppt/slideMasters/_rels/slideMaster1.xml.rels': rels([('rId1', 'theme', '../theme/theme1.xml'), ('rId2', 'slideLayout', '../slideLayouts/slideLayout1.xml')]),
        'ppt/theme/theme1.xml': xml(theme)
    }
    write_zip(path, files)


def illustrator(path):
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.276 841.89] /Resources << >> /Contents 4 0 R >>',
               b'<< /Length 0 >>\nstream\n\nendstream', b'<< /Creator (Crab) /Title (Blank) >>']
    data = bytearray(b'%PDF-1.5\n%\xe2\xe3\xcf\xd3\n'); offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(data)); data += ('%d 0 obj\n' % i).encode() + obj + b'\nendobj\n'
    xref = len(data)
    data += ('xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)).encode()
    data += ''.join('%010d 00000 n \n' % offset for offset in offsets[1:]).encode()
    data += ('trailer\n<< /Size %d /Root 1 0 R /Info 5 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)).encode()
    path.write_bytes(data)


def photoshop(path):
    width, height = 1890, 1417
    row = bytearray()
    for start in range(0, width, 128):
        count = min(128, width - start)
        row += bytes([257 - count, 255]) if count > 1 else bytes([0, 255])
    header = b'8BPS' + struct.pack('>H6sHIIHH', 1, b'\0' * 6, 3, height, width, 8, 3)
    data = header + struct.pack('>IIIH', 0, 0, 0, 1)
    data += struct.pack('>H', len(row)) * (height * 3) + bytes(row) * (height * 3)
    path.write_bytes(data)


def sanitize_ole(source):
    data = bytearray(source)
    if data[:8] != bytes.fromhex('d0cf11e0a1b11ae1'): raise ValueError('Not a compound document')
    sector_size = 1 << struct.unpack_from('<H', data, 30)[0]
    mini_size = 1 << struct.unpack_from('<H', data, 32)[0]
    def sector(sid): return 512 + sid * sector_size
    fat = []
    for sid in struct.unpack_from('<109I', data, 76):
        if sid < 0xFFFFFFFA: fat.extend(struct.unpack_from('<%dI' % (sector_size // 4), data, sector(sid)))
    def chain(start, table):
        result = []; seen = set()
        while start < 0xFFFFFFFA:
            if start in seen or start >= len(table): raise ValueError('Invalid compound chain')
            seen.add(start); result.append(start); start = table[start]
        return result
    directory_ids = chain(struct.unpack_from('<I', data, 48)[0], fat)
    directory = b''.join(data[sector(sid):sector(sid)+sector_size] for sid in directory_ids)
    entries = []
    for pos in range(0, len(directory), 128):
        item = directory[pos:pos+128]
        length = struct.unpack_from('<H', item, 64)[0]
        if not length: continue
        entries.append((item[:length-2].decode('utf-16le'), item[66], struct.unpack_from('<I', item, 116)[0], struct.unpack_from('<Q', item, 120)[0]))
    root = next(entry for entry in entries if entry[1] == 5)
    root_ids = chain(root[2], fat)
    mini_fat_bytes = b''.join(data[sector(sid):sector(sid)+sector_size] for sid in chain(struct.unpack_from('<I', data, 60)[0], fat))
    mini_fat = struct.unpack('<%dI' % (len(mini_fat_bytes)//4), mini_fat_bytes) if mini_fat_bytes else []
    cleared = []
    for name, kind, first, length in entries:
        if kind != 2 or name != '\x05SummaryInformation': continue
        locations = []
        if length < 4096:
            for sid in chain(first, mini_fat):
                for offset in range(mini_size):
                    logical = sid * mini_size + offset
                    locations.append(sector(root_ids[logical // sector_size]) + logical % sector_size)
        else:
            for sid in chain(first, fat): locations.extend(range(sector(sid), sector(sid)+sector_size))
        locations = locations[:length]
        stream = bytearray(data[pos] for pos in locations)
        sections = struct.unpack_from('<I', stream, 24)[0]
        for section_index in range(sections):
            begin = struct.unpack_from('<I', stream, 44 + section_index * 20)[0]
            size, count = struct.unpack_from('<II', stream, begin)
            props = [struct.unpack_from('<II', stream, begin+8+i*8) for i in range(count)]
            ends = sorted(offset for _, offset in props) + [size]
            for pid, offset in props:
                if pid not in [2, 3, 4, 6, 8]: continue
                pos = begin + offset; variant = struct.unpack_from('<I', stream, pos)[0]
                if variant not in [30, 31]: continue
                end = begin + next(value for value in ends if value > offset)
                stream[pos+4:end] = b'\0' * (end-pos-4)
                struct.pack_into('<I', stream, pos+4, 1)
                cleared.append(pid)
        for pos, value in zip(locations, stream): data[pos] = value
    return bytes(data), [entry[0] for entry in entries], cleared


def main():
    parser = argparse.ArgumentParser(description="Generate blank PPTX / PDF-compatible AI / RGB PSD without third-party packages.\n\nOptional --import-original APP copies only six verified generic blank data files\nfrom that installed application's Resources. WPS author/title/comment properties\nare cleared in the copies; executable code and brand artwork are never imported.\nExisting Word/Excel resources are intentionally outside this script's ownership.\n")
    parser.add_argument('destination', type=Path)
    parser.add_argument('--import-original', type=Path)
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args(); args.destination.mkdir(parents=True, exist_ok=True)
    powerpoint(args.destination / 'Blank.pptx')
    illustrator(args.destination / 'Blank.ai')
    photoshop(args.destination / 'Blank.psd')
    manifest = {'generated': ['Blank.pptx', 'Blank.ai', 'Blank.psd'], 'imports': []}
    if args.import_original:
        resources = args.import_original / 'Contents/Resources'
        for original, target in [('Pages.pages', 'Blank.pages'), ('Numbers.numbers', 'Blank.numbers'), ('Keynote.key', 'Blank.key'), ('WPS_wps.wps', 'Blank.wps'), ('WPS_et.et', 'Blank.et'), ('WPS_dps.dps', 'Blank.dps')]:
            source = (resources / original).read_bytes()
            record = {'original': original, 'target': target, 'sourceSHA256': hashlib.sha256(source).hexdigest()}
            if original.startswith('WPS_'):
                output, streams, cleared = sanitize_ole(source)
                record.update(streams=streams, clearedSummaryPropertyIDs=cleared)
            else:
                with zipfile.ZipFile(resources / original) as archive:
                    assert archive.testzip() is None
                    assert any(name.startswith('Index/') and name.endswith('.iwa') for name in archive.namelist())
                    history = plistlib.loads(archive.read('Metadata/BuildVersionHistory.plist'))
                    assert any('Template: Blank' in item or 'Template: White' in item for item in history)
                    record['templateHistory'] = history
                output = source
            (args.destination / target).write_bytes(output)
            record['outputSHA256'] = hashlib.sha256(output).hexdigest(); manifest['imports'].append(record)
    manifest['files'] = {path.name: {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in args.destination.glob('Blank.*')}
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()
