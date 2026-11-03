r"""Reads a Portal 2 model straight from the game's VPKs: skeleton, attachments, the animations of the model it
includes ($includemodel), and its mesh (bind pose, bone weights). Enough for the ending's first-person body,
models/player/chell/headless_player.mdl (animations in models/headless_player_animations.mdl/.ani).

Formats (MDL v49 / VVD v4 / VTX v7, as Portal 2 ships them):
  MDL   studiohdr_t: bones (216 bytes each), attachments (92), sequences (212), animdescs (100), includes, animblocks
  ANI   animation blocks the animdescs point into (mstudioanimblock_t datastart/dataend)
  VVD   vertices (48 bytes: weights, bones, position, normal, uv), LOD fixups
  VTX   strip groups: per-mesh vertex lists (origMeshVertID) and triangle indices
Animation data (bone_setup.cpp's CalcBonePosition/CalcBoneQuaternion): per bone an mstudioanim_t chain - raw
Quaternion48/64 and Vector48, or RLE-compressed per-channel values scaled by the bone's rotscale/posscale and added
to its default rot/pos; long animations are cut in sections (sectionframes), the last frame stored on its own.

Nothing here is written anywhere: it reads the user's own install.
"""
import math
import os
import struct

P2 = r"C:\Program Files (x86)\Steam\steamapps\common\Portal 2"

# ---- VPK ----


class Vpk:
    """One _dir.vpk: name -> bytes."""

    def __init__(self, path):
        self.path = path
        self.entries = {}
        with open(path, 'rb') as f:
            sig, ver, tree = struct.unpack('<III', f.read(12))
            header = 12
            if ver == 2:
                f.read(16)
                header = 28

            def rs():
                b = bytearray()
                while True:
                    c = f.read(1)
                    if c in (b'\0', b''):
                        return b.decode('latin1')
                    b += c

            while True:
                ext = rs()
                if not ext:
                    break
                while True:
                    d = rs()
                    if not d:
                        break
                    while True:
                        n = rs()
                        if not n:
                            break
                        crc, pre, idx, off, ln, term = struct.unpack('<IHHIIH', f.read(18))
                        preload = f.read(pre)
                        name = (n + '.' + ext) if d.strip() == '' else '%s/%s.%s' % (d, n, ext)
                        self.entries[name.lower()] = (idx, off, ln, preload)
            self.data_start = header + tree

    def read(self, name):
        e = self.entries.get(name.lower())
        if e is None:
            return None
        idx, off, ln, preload = e
        data = preload
        if ln:
            if idx == 0x7FFF:
                with open(self.path, 'rb') as f:
                    f.seek(self.data_start + off)
                    data += f.read(ln)
            else:
                with open(self.path.replace('_dir.vpk', '_%03d.vpk' % idx), 'rb') as f:
                    f.seek(off)
                    data += f.read(ln)
        return data


class GameFiles:
    """Portal 2's files the way the game finds them: loose files and VPKs, update/ before portal2/."""

    def __init__(self, root=P2):
        self.dirs = [os.path.join(root, d) for d in ('update', 'portal2_dlc2', 'portal2_dlc1', 'portal2')]
        self.vpks = []
        for d in self.dirs:
            p = os.path.join(d, 'pak01_dir.vpk')
            if os.path.exists(p):
                self.vpks.append(Vpk(p))

    def read(self, name):
        for d in self.dirs:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return open(p, 'rb').read()
        for v in self.vpks:
            data = v.read(name)
            if data is not None:
                return data
        return None


# ---- math (Source conventions: quaternions x, y, z, w; matrices 3x4 row-major, column 3 the translation) ----


def angle_quaternion(x, y, z):
    """RadianEuler (roll x, pitch y, yaw z) -> quaternion (mathlib AngleQuaternion)."""
    sy, cy = math.sin(z * 0.5), math.cos(z * 0.5)
    sp, cp = math.sin(y * 0.5), math.cos(y * 0.5)
    sr, cr = math.sin(x * 0.5), math.cos(x * 0.5)
    srXcp, crXsp = sr * cp, cr * sp
    crXcp, srXsp = cr * cp, sr * sp
    return (srXcp * cy - crXsp * sy, crXsp * cy + srXcp * sy, crXcp * sy - srXsp * cy, crXcp * cy + srXsp * sy)


def quat_matrix(q, p):
    x, y, z, w = q
    return [
        [1.0 - 2.0 * y * y - 2.0 * z * z, 2.0 * x * y - 2.0 * w * z, 2.0 * x * z + 2.0 * w * y, p[0]],
        [2.0 * x * y + 2.0 * w * z, 1.0 - 2.0 * x * x - 2.0 * z * z, 2.0 * y * z - 2.0 * w * x, p[1]],
        [2.0 * x * z - 2.0 * w * y, 2.0 * y * z + 2.0 * w * x, 1.0 - 2.0 * x * x - 2.0 * y * y, p[2]],
    ]


def concat(a, b):
    """3x4 a * 3x4 b."""
    out = []
    for i in range(3):
        r = []
        for j in range(4):
            v = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]
            if j == 3:
                v += a[i][3]
            r.append(v)
        out.append(r)
    return out


def half(h):
    return struct.unpack('<e', struct.pack('<H', h))[0]


def quat48(b):
    x, y, zw = struct.unpack('<HHH', b)
    z, wneg = zw & 0x7FFF, zw >> 15
    qx = (x - 32768) * (1.0 / 32768.0)
    qy = (y - 32768) * (1.0 / 32768.0)
    qz = (z - 16384) * (1.0 / 16384.0)
    qw = math.sqrt(max(0.0, 1.0 - qx * qx - qy * qy - qz * qz))
    return (qx, qy, qz, -qw if wneg else qw)


def quat64(b):
    v = struct.unpack('<Q', b)[0]
    x, y, z, wneg = v & 0x1FFFFF, (v >> 21) & 0x1FFFFF, (v >> 42) & 0x1FFFFF, v >> 63
    qx = (x - 1048576) * (1.0 / 1048576.5)
    qy = (y - 1048576) * (1.0 / 1048576.5)
    qz = (z - 1048576) * (1.0 / 1048576.5)
    qw = math.sqrt(max(0.0, 1.0 - qx * qx - qy * qy - qz * qz))
    return (qx, qy, qz, -qw if wneg else qw)


def cstr(d, o):
    return d[o:d.index(b'\0', o)].decode('latin1')


# ---- MDL ----

STUDIO_ANIM_RAWPOS, STUDIO_ANIM_RAWROT, STUDIO_ANIM_ANIMPOS, STUDIO_ANIM_ANIMROT, STUDIO_ANIM_DELTA, STUDIO_ANIM_RAWROT2 = (
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20)
# animdesc flag: frame animation (mstudio_frame_anim_t), and its per-bone flags
STUDIO_FRAMEANIM = 0x40
STUDIO_FRAME_CONST_POS, STUDIO_FRAME_CONST_ROT, STUDIO_FRAME_ANIM_POS, STUDIO_FRAME_ANIM_ROT = 0x01, 0x02, 0x04, 0x08


class Bone:
    def __init__(self, d, o):
        sn, self.parent = struct.unpack_from('<ii', d, o)
        self.name = cstr(d, o + sn)
        self.pos = struct.unpack_from('<3f', d, o + 32)
        self.quat = struct.unpack_from('<4f', d, o + 44)
        self.rot = struct.unpack_from('<3f', d, o + 60)
        self.posscale = struct.unpack_from('<3f', d, o + 72)
        self.rotscale = struct.unpack_from('<3f', d, o + 84)
        m = struct.unpack_from('<12f', d, o + 96)
        self.pose_to_bone = [list(m[0:4]), list(m[4:8]), list(m[8:12])]


class Mdl:
    def __init__(self, data, ani=None):
        d = self.d = data
        self.ani = ani
        ident, self.version = struct.unpack_from('<4si', d, 0)
        if ident != b'IDST':
            raise ValueError('not an MDL')
        self.name = cstr(d, 12)
        nb, bi = struct.unpack_from('<ii', d, 156)
        self.bones = [Bone(d, bi + i * 216) for i in range(nb)]
        na, ai, ns, si = struct.unpack_from('<iiii', d, 180)
        self.animindex = ai
        self.numanims = na
        self.sequences = []
        for i in range(ns):
            o = si + i * 212
            lab = struct.unpack_from('<i', d, o + 4)[0]
            flags = struct.unpack_from('<i', d, o + 12)[0]
            numblends, animindexindex = struct.unpack_from('<ii', d, o + 56)
            anim = struct.unpack_from('<h', d, o + animindexindex)[0]
            self.sequences.append({'name': cstr(d, o + lab), 'flags': flags, 'anim': anim})
        nat, ati = struct.unpack_from('<ii', d, 240)
        self.attachments = {}
        for i in range(nat):
            o = ati + i * 92
            sn, flags, bone = struct.unpack_from('<iii', d, o)
            m = struct.unpack_from('<12f', d, o + 12)
            self.attachments[cstr(d, o + sn)] = {'bone': bone, 'matrix': [list(m[0:4]), list(m[4:8]), list(m[8:12])]}
        ninc, inci = struct.unpack_from('<ii', d, 336)
        self.includes = []
        for i in range(ninc):
            o = inci + i * 8
            lab, nm = struct.unpack_from('<ii', d, o)
            self.includes.append(cstr(d, o + nm))
        self.numanimblocks, self.animblockindex = struct.unpack_from('<ii', d, 352)
        self.numbodyparts, self.bodypartindex = struct.unpack_from('<ii', d, 232)

    # -- animation --
    def animdesc(self, i):
        o = self.animindex + i * 100
        d = self.d
        sn = struct.unpack_from('<i', d, o + 4)[0]
        fps, flags, numframes = struct.unpack_from('<fii', d, o + 8)
        animblock, animindex = struct.unpack_from('<ii', d, o + 52)
        sectionindex, sectionframes = struct.unpack_from('<ii', d, o + 80)
        return {'offset': o, 'name': cstr(d, o + sn), 'fps': fps, 'flags': flags, 'frames': numframes, 'animblock': animblock,
                'animindex': animindex, 'sectionindex': sectionindex, 'sectionframes': sectionframes}

    def _block(self, block):
        """(bytes, base offset) of an animation block: 0 is the MDL itself."""
        if block == 0:
            return self.d, 0
        o = self.animblockindex + block * 8
        start, end = struct.unpack_from('<ii', self.d, o)
        if self.ani is None:
            raise ValueError('animation block %d needs the .ani file' % block)
        return self.ani, start

    def _anim_chain(self, ad, frame):
        """(bytes, offset of the first mstudioanim_t, frame within it) for a frame of an animdesc."""
        block, index = ad['animblock'], ad['animindex']
        sf, n = ad['sectionframes'], ad['frames']
        rel = ad['offset']  # block 0: relative to the animdesc
        if sf != 0:
            if n > sf and frame == n - 1:
                frame, section = 0, n // sf + 1
            else:
                section = frame // sf
                frame -= section * sf
            so = ad['offset'] + ad['sectionindex'] + section * 8
            block, index = struct.unpack_from('<ii', self.d, so)
        if block == 0:
            return self.d, rel + index, frame
        data, base = self._block(block)
        return data, base + index, frame

    def bone_locals(self, anim_index, frame):
        """Local (pos, quat) of each of this model's bones at an integer frame of an animation."""
        ad = self.animdesc(anim_index)
        frame = max(0, min(ad['frames'] - 1, frame))
        out = [(b.pos, b.quat) for b in self.bones]
        d, o, fr = self._anim_chain(ad, frame)
        if ad['flags'] & STUDIO_FRAMEANIM:
            return self._frame_anim(d, o, fr, out)
        while True:
            bone, flags, nxt = struct.unpack_from('<BBh', d, o)
            if bone < len(self.bones):
                b = self.bones[bone]
                delta = (flags & STUDIO_ANIM_DELTA) != 0
                data = o + 4
                # rotation
                if flags & STUDIO_ANIM_RAWROT:
                    q = quat48(d[data:data + 6])
                elif flags & STUDIO_ANIM_RAWROT2:
                    q = quat64(d[data:data + 8])
                elif flags & STUDIO_ANIM_ANIMROT:
                    vp = data
                    ang = [0.0, 0.0, 0.0]
                    for j in range(3):
                        off = struct.unpack_from('<h', d, vp + j * 2)[0]
                        ang[j] = extract_anim_value(d, vp + off, fr, b.rotscale[j]) if off else 0.0
                        if not delta:
                            ang[j] += b.rot[j]
                    q = angle_quaternion(*ang)
                else:
                    q = (0.0, 0.0, 0.0, 1.0) if delta else b.quat
                # position
                if flags & STUDIO_ANIM_RAWPOS:
                    po = data + (6 if flags & STUDIO_ANIM_RAWROT else 0) + (8 if flags & STUDIO_ANIM_RAWROT2 else 0)
                    p = tuple(half(h) for h in struct.unpack_from('<3H', d, po))
                elif flags & STUDIO_ANIM_ANIMPOS:
                    vp = data + (6 if flags & STUDIO_ANIM_ANIMROT else 0)
                    p = [0.0, 0.0, 0.0]
                    for j in range(3):
                        off = struct.unpack_from('<h', d, vp + j * 2)[0]
                        p[j] = extract_anim_value(d, vp + off, fr, b.posscale[j]) if off else 0.0
                        if not delta:
                            p[j] += b.pos[j]
                    p = tuple(p)
                else:
                    p = (0.0, 0.0, 0.0) if delta else b.pos
                out[bone] = (p, q)
            if nxt == 0:
                break
            o += nxt
        return out

    def _frame_anim(self, d, o, frame, out):
        """mstudio_frame_anim_t (Portal 2's animations): a flags byte per bone, then for each bone in order its constant
        rotation (Quaternion48) and/or position (Vector48), or those values in each frame's block; no flag: the bone's
        default."""
        constantsoffset, frameoffset, framelength = struct.unpack_from('<iii', d, o)
        flags = d[o + 24:o + 24 + len(self.bones)]
        c = o + constantsoffset
        f = o + frameoffset + frame * framelength
        for i, fl in enumerate(flags):
            b = self.bones[i]
            q, p = b.quat, b.pos
            if fl & STUDIO_FRAME_CONST_ROT:
                q = quat48(d[c:c + 6])
                c += 6
            elif fl & STUDIO_FRAME_ANIM_ROT:
                q = quat48(d[f:f + 6])
                f += 6
            if fl & STUDIO_FRAME_CONST_POS:
                p = tuple(half(h) for h in struct.unpack_from('<3H', d, c))
                c += 6
            elif fl & STUDIO_FRAME_ANIM_POS:
                p = tuple(half(h) for h in struct.unpack_from('<3H', d, f))
                f += 6
            if fl & 0xF0:
                raise ValueError('bone %s: frame animation flags 0x%x not known' % (b.name, fl))
            out[i] = (p, q)
        return out

    # -- mesh --
    def mesh(self, vvd, vtx):
        """Bind-pose triangles of LOD 0: positions (model space), bone weights, indices."""
        verts = read_vvd(vvd)
        positions, weights, indices = [], [], []
        vh = struct.unpack_from('<iiHHiiiiii', vtx, 0)
        num_bp_vtx, bp_off_vtx = vh[8], vh[9]
        d = self.d
        for bp in range(self.numbodyparts):
            o = self.bodypartindex + bp * 16
            sn, nm, base, mi = struct.unpack_from('<iiii', d, o)
            vbp = bp_off_vtx + bp * 8
            vnm, vmo = struct.unpack_from('<ii', vtx, vbp)
            for mdl_i in range(nm):
                mo = o + mi + mdl_i * 148
                nmesh, meshidx, nverts, vertexindex = struct.unpack_from('<iiii', d, mo + 72)
                model_base = vertexindex // 48
                vmodel = vbp + vmo + mdl_i * 8
                nlods, lodoff = struct.unpack_from('<ii', vtx, vmodel)
                vlod = vmodel + lodoff
                vnmesh, vmeshoff = struct.unpack_from('<ii', vtx, vlod)
                for me in range(nmesh):
                    mesh_o = mo + meshidx + me * 116
                    vertexoffset = struct.unpack_from('<i', d, mesh_o + 12)[0]
                    vmesh = vlod + vmeshoff + me * 9
                    nsg, sgoff = struct.unpack_from('<ii', vtx, vmesh)
                    for g in range(nsg):
                        sg = vmesh + sgoff + g * self._sg_size(vtx, vmesh + sgoff, nsg)
                        nv, voff, ni, ioff = struct.unpack_from('<iiii', vtx, sg)
                        first = len(positions)
                        for k in range(nv):
                            vo = sg + voff + k * 9
                            orig = struct.unpack_from('<H', vtx, vo + 4)[0]
                            v = verts[model_base + vertexoffset + orig]
                            positions.append(v['pos'])
                            weights.append(v['weights'])
                        idx = struct.unpack_from('<%dH' % ni, vtx, sg + ioff)
                        if any(i >= nv for i in idx):
                            raise ValueError('strip group indices out of range (wrong strip group size?)')
                        # (Source's triangles wind clockwise; three.js wants counter-clockwise)
                        for t in range(0, ni - 2, 3):
                            indices.extend((first + idx[t], first + idx[t + 2], first + idx[t + 1]))
        return positions, weights, indices

    _sg = None

    def _sg_size(self, vtx, first, n):
        """Strip group header size: 25 bytes, or 33 with the topology fields of later VTX files."""
        if self._sg is None:
            self._sg = 25
            if n > 1:
                a = struct.unpack_from('<iiii', vtx, first + 25)
                if not (0 < a[0] < 65536 and 0 < a[2] < 1 << 20):
                    self._sg = 33
        return self._sg


def extract_anim_value(d, o, frame, scale):
    """bone_setup.cpp ExtractAnimValue: RLE runs of (valid, total) headers and shorts."""
    k = frame
    while True:
        valid, total = struct.unpack_from('<BB', d, o)
        if total == 0:
            return 0.0
        if total > k:
            break
        k -= total
        o += (valid + 1) * 2
    if valid > k:
        return struct.unpack_from('<h', d, o + (k + 1) * 2)[0] * scale
    return struct.unpack_from('<h', d, o + valid * 2)[0] * scale


def read_vvd(d):
    ident, ver, chk, nlods = struct.unpack_from('<4siii', d, 0)
    lodverts = struct.unpack_from('<8i', d, 16)
    nfix, fixstart, vstart, tstart = struct.unpack_from('<iiii', d, 48)

    def vert(i):
        o = vstart + i * 48
        w = struct.unpack_from('<3f', d, o)
        b = struct.unpack_from('<3bB', d, o + 12)
        pos = struct.unpack_from('<3f', d, o + 16)
        n = b[3]
        return {'pos': pos, 'weights': [(b[j], w[j]) for j in range(n)]}

    if nfix == 0:
        return [vert(i) for i in range(lodverts[0])]
    out = []
    for f in range(nfix):
        lod, src, num = struct.unpack_from('<iii', d, fixstart + f * 12)
        if lod >= 0:
            out.extend(vert(src + i) for i in range(num))
    return out


# ---- the ending's body ----

BODY = 'models/player/chell/headless_player'


class Body:
    """headless_player.mdl with the animations it includes, posed in model space."""

    def __init__(self, files=None):
        files = files or GameFiles()
        self.base = Mdl(files.read(BODY + '.mdl'))
        self.anims = []
        for inc in self.base.includes:
            stem = inc[:-4]
            self.anims.append(Mdl(files.read(inc), files.read(stem + '.ani')))
        self.vvd = files.read(BODY + '.vvd')
        self.vtx = files.read(BODY + '.dx90.vtx')
        # each included model's bones -> the base model's bones, by name (as the engine's virtual model maps them)
        index = {b.name.lower(): i for i, b in enumerate(self.base.bones)}
        self.maps = [[index.get(b.name.lower(), -1) for b in a.bones] for a in self.anims]
        self.sequences = []
        for ai, a in enumerate(self.anims):
            for s in a.sequences:
                ad = a.animdesc(s['anim'])
                self.sequences.append({'name': s['name'], 'model': ai, 'anim': s['anim'], 'frames': ad['frames'], 'fps': ad['fps'],
                                       'loop': bool(s['flags'] & 1)})

    def bone_matrices(self, seq, frame):
        """Model-space 3x4 matrix of each base bone at an integer frame of a sequence."""
        s = self.sequences[seq]
        a, m = self.anims[s['model']], self.maps[s['model']]
        locs = [(b.pos, b.quat) for b in self.base.bones]
        for i, (p, q) in enumerate(a.bone_locals(s['anim'], frame)):
            if m[i] >= 0:
                locs[m[i]] = (p, q)
        world = []
        for i, b in enumerate(self.base.bones):
            local = quat_matrix(locs[i][1], locs[i][0])
            world.append(local if b.parent < 0 else concat(world[b.parent], local))
        return world
