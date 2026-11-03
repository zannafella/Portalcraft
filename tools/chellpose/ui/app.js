// Ending Arms: Minecraft's arms posed on Chell's first-person arms in Portal 2's ending (see ../server.py).
//
// Everything below works in Portal 2's model space (Source units, z up) inside `src`, a group turned so three.js's y
// is up. Each arm: socket (where it follows: shoulder -> wrist, or a bone; set every frame) > offset (what you pose:
// keyframed per animation, the gizmo moves it) > px (Minecraft's model space for the arm: pixels, its pivot at the
// shoulder, +y down the arm; 2 Source units a pixel) > the arm and sleeve cubes, built exactly as Minecraft builds its
// player model (ModelPart.Cube), so the export lines up with what Minecraft draws in the game.
import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { TransformControls } from 'three/addons/controls/TransformControls.js';

const $ = (id) => document.getElementById(id);
const status = (text, bad = false) => {
	$('status').textContent = text;
	$('status').className = bad ? 'bad' : '';
};
async function api(path, opt) {
	const r = await fetch(path, opt);
	if (!r.ok) {
		let msg = r.statusText;
		try {
			msg = (await r.json()).error || msg;
		} catch (e) {}
		throw new Error(msg);
	}
	return r;
}

// ---- Portal 2's body ----
let body;
try {
	body = await (await api('/api/body')).json();
} catch (e) {
	$('loading').textContent = "Couldn't read Portal 2's model: " + e.message;
	throw e;
}
$('loading').remove();
const NB = body.bones.length;
const boneIndex = Object.fromEntries(body.bones.map((b, i) => [b.name, i]));
const SEQS = body.sequences;
const seqCache = {};
async function seqData(i) {
	if (!seqCache[i]) seqCache[i] = new Float32Array(await (await api('/api/seq/' + i)).arrayBuffer());
	return seqCache[i];
}
const m4 = (a, o = 0) => new THREE.Matrix4().set(a[o], a[o + 1], a[o + 2], a[o + 3], a[o + 4], a[o + 5], a[o + 6], a[o + 7], a[o + 8], a[o + 9], a[o + 10], a[o + 11], 0, 0, 0, 1);
const poseToBone = body.bones.map((b) => m4(b.poseToBone));
const eyes = body.attachments['vehicle_driver_eyes'];
const eyesLocal = m4(eyes.matrix);
function boneMatrix(data, frame, b, out = new THREE.Matrix4()) {
	const o = (frame * NB + b) * 12;
	return out.set(data[o], data[o + 1], data[o + 2], data[o + 3], data[o + 4], data[o + 5], data[o + 6], data[o + 7], data[o + 8], data[o + 9], data[o + 10], data[o + 11], 0, 0, 0, 1);
}

// ---- scene ----
const view = $('view');
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(window.devicePixelRatio);
view.appendChild(renderer.domElement);
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x0e1013);
scene.add(new THREE.AmbientLight(0xffffff, 0.7));
const sun = new THREE.DirectionalLight(0xffffff, 1.2);
sun.position.set(1, 2, 1.5);
scene.add(sun);
const src = new THREE.Group();
src.rotation.x = -Math.PI / 2; // Source (x, y, z) -> three (x, z, -y)
scene.add(src);
src.updateMatrixWorld(true);

const cameraFP = new THREE.PerspectiveCamera(73.74, 1, 0.5, 8000);
cameraFP.matrixAutoUpdate = false;
const cameraOrbit = new THREE.PerspectiveCamera(50, 1, 0.5, 8000);
cameraOrbit.position.set(60, 40, 60);
const orbit = new OrbitControls(cameraOrbit, renderer.domElement);
orbit.enableDamping = true;
let firstPerson = true;
const activeCamera = () => (firstPerson ? cameraFP : cameraOrbit);
// camera axes -> Source: right = -y, up = +z, back = -x (Source looks down +x)
const CAM = new THREE.Matrix4().set(0, 0, -1, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1);

// Chell's arms (skinned on the CPU: 2600 vertices)
const meshPos = new Float32Array(body.mesh.positions);
const chellGeo = new THREE.BufferGeometry();
const chellPos = new Float32Array(meshPos.length);
chellGeo.setAttribute('position', new THREE.BufferAttribute(chellPos, 3).setUsage(THREE.DynamicDrawUsage));
chellGeo.setIndex(body.mesh.indices);
const chellMat = new THREE.MeshLambertMaterial({ color: 0xd8d2c8, transparent: true, opacity: 0.45, side: THREE.DoubleSide, depthWrite: false });
const chell = new THREE.Mesh(chellGeo, chellMat);
chell.frustumCulled = false;
src.add(chell);
const skinIdx = body.mesh.skinIndex, skinW = body.mesh.skinWeight;
const skinM = Array.from({ length: NB }, () => new THREE.Matrix4());

const boneGeo = new THREE.BufferGeometry();
const bonePos = new Float32Array(NB * 6);
boneGeo.setAttribute('position', new THREE.BufferAttribute(bonePos, 3).setUsage(THREE.DynamicDrawUsage));
const bones = new THREE.LineSegments(boneGeo, new THREE.LineBasicMaterial({ color: 0xff5050, depthTest: false }));
bones.frustumCulled = false;
bones.renderOrder = 10;
bones.visible = false;
src.add(bones);

// ---- Minecraft's arm (ModelPart.Cube, 64x64 skin) ----
function mcCube(x0, y0, z0, w, h, d, u, v, inflate) {
	const a = x0 - inflate, b = y0 - inflate, c = z0 - inflate;
	const A = x0 + w + inflate, B = y0 + h + inflate, C = z0 + d + inflate;
	const v1 = [a, b, c], v2 = [A, b, c], v3 = [A, B, c], v4 = [a, B, c], v5 = [a, b, C], v6 = [A, b, C], v7 = [A, B, C], v8 = [a, B, C];
	const f = u, g = v, hh = u + d, i = u + d + w, j = u + d + w + w, k = u + d + w + d, l = u + d + w + d + w, m = v + d, n = v + d + h;
	const polys = [
		[[v6, v5, v1, v2], hh, g, i, m],
		[[v3, v4, v8, v7], i, m, j, g],
		[[v1, v5, v8, v4], f, m, hh, n],
		[[v2, v1, v4, v3], hh, m, i, n],
		[[v6, v2, v3, v7], i, m, k, n],
		[[v5, v6, v7, v8], k, m, l, n],
	];
	const pos = [], uv = [], idx = [];
	for (const [vs, u0, v0, u1, v1_] of polys) {
		const base = pos.length / 3;
		const uvs = [[u1, v0], [u0, v0], [u0, v1_], [u1, v1_]];
		vs.forEach((p, q) => {
			pos.push(...p);
			uv.push(uvs[q][0] / 64, 1 - uvs[q][1] / 64);
		});
		idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
	}
	const g2 = new THREE.BufferGeometry();
	g2.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
	g2.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
	g2.setIndex(idx);
	return g2;
}
const ARMS = {
	right: { wide: [-3, -2, -2, 4], slim: [-2, -2, -2, 3], uv: [40, 16], sleeve: [40, 32], shoulder: 'bicep_R', wrist: 'wrist_R' },
	left: { wide: [-1, -2, -2, 4], slim: [-1, -2, -2, 3], uv: [32, 48], sleeve: [48, 48], shoulder: 'bicep_L', wrist: 'wrist_L' },
};
// Minecraft's arm space (pixels, +y down the arm) -> the part's space (Source units, +x down the arm): 2 units a pixel
const PX = new THREE.Matrix4().set(0, 2, 0, 0, 2, 0, 0, 0, 0, 0, -2, 0, 0, 0, 0, 1);
const ARM_REACH = 20; // pivot -> hand end, Source units (Minecraft's arm runs 10 pixels below its pivot)

const skinTex = new THREE.Texture();
skinTex.magFilter = skinTex.minFilter = THREE.NearestFilter;
skinTex.generateMipmaps = false;
skinTex.colorSpace = THREE.SRGBColorSpace;
const armMat = new THREE.MeshBasicMaterial({ map: skinTex, side: THREE.DoubleSide, alphaTest: 0.5 });
async function loadSkin(url) {
	const img = new Image();
	await new Promise((ok, fail) => {
		img.onload = ok;
		img.onerror = () => fail(new Error("couldn't read the skin image"));
		img.src = url;
	});
	skinTex.image = img;
	skinTex.needsUpdate = true;
}

const parts = {};
for (const key of ['right', 'left']) {
	const socket = new THREE.Object3D();
	socket.matrixAutoUpdate = false;
	const offset = new THREE.Object3D();
	const px = new THREE.Object3D();
	px.matrixAutoUpdate = false;
	socket.add(offset);
	offset.add(px);
	src.add(socket);
	parts[key] = { socket, offset, px, meshes: [] };
}
function buildArms(slim) {
	for (const [key, p] of Object.entries(parts)) {
		p.meshes.forEach((m) => {
			p.px.remove(m);
			m.geometry.dispose();
		});
		const def = ARMS[key];
		const [x, y, z, w] = slim ? def.slim : def.wide;
		const arm = new THREE.Mesh(mcCube(x, y, z, w, 12, 4, def.uv[0], def.uv[1], 0), armMat);
		const sleeve = new THREE.Mesh(mcCube(x, y, z, w, 12, 4, def.sleeve[0], def.sleeve[1], 0.25), armMat);
		p.meshes = [arm, sleeve];
		p.px.add(arm, sleeve);
	}
}

// ---- the project (your poses) ----
const DEFAULT_PART = () => ({ mode: 'aim', bone: '', stretch: true, visible: true, keys: {} });
let project = { version: 1, slim: false, parts: { right: DEFAULT_PART(), left: DEFAULT_PART() } };
try {
	const p = await (await api('/api/project')).json();
	if (p && p.parts) project = Object.assign(project, p);
} catch (e) {
	status("Couldn't load pose.json: " + e.message, true);
}
for (const k of ['right', 'left']) project.parts[k] = Object.assign(DEFAULT_PART(), project.parts[k] || {});
let dirty = false;

// ---- state ----
let seq = SEQS.findIndex((s) => s.name === 'Ending_Hang_Loop');
if (seq < 0) seq = 0;
let frame = 0, playing = false, playT = 0;
let current = 'right';
let data = await seqData(seq);
const tmpA = new THREE.Matrix4(), tmpB = new THREE.Matrix4(), tmpC = new THREE.Matrix4();
const vA = new THREE.Vector3(), vB = new THREE.Vector3(), vC = new THREE.Vector3(), vD = new THREE.Vector3();

const IDENT = () => ({ f: 0, p: [0, 0, 0], q: [0, 0, 0, 1], s: [1, 1, 1] });
function keysOf(part, seqName) {
	return (project.parts[part].keys[seqName] ||= []);
}
/** The offset of a part at a frame: its keys, interpolated (nothing keyed: no offset). */
function offsetAt(part, seqName, f) {
	const keys = project.parts[part].keys[seqName] || [];
	if (!keys.length) return IDENT();
	if (f <= keys[0].f) return keys[0];
	if (f >= keys[keys.length - 1].f) return keys[keys.length - 1];
	let i = 0;
	while (keys[i + 1].f < f) i++;
	const a = keys[i], b = keys[i + 1], t = (f - a.f) / (b.f - a.f);
	const q = new THREE.Quaternion(...a.q).slerp(new THREE.Quaternion(...b.q), t);
	return { f, p: a.p.map((x, j) => x + (b.p[j] - x) * t), q: [q.x, q.y, q.z, q.w], s: a.s.map((x, j) => x + (b.s[j] - x) * t) };
}

/** Where a part follows at a frame (socket matrix, Source model space) and how much its arm stretches. */
function socketAt(part, d, f, out) {
	const cfg = project.parts[part];
	if (cfg.mode === 'bone' && boneIndex[cfg.bone] !== undefined) {
		boneMatrix(d, f, boneIndex[cfg.bone], out);
		return 1;
	}
	// aimed: from the shoulder (bicep) toward the wrist, rolled as the upper arm is
	const def = ARMS[part];
	const sh = boneMatrix(d, f, boneIndex[def.shoulder], tmpA), wr = boneMatrix(d, f, boneIndex[def.wrist], tmpB);
	vA.setFromMatrixPosition(sh);
	vB.setFromMatrixPosition(wr);
	const len = vB.distanceTo(vA);
	const x = vB.sub(vA).normalize();
	const ref = vC.setFromMatrixColumn(sh, 2).normalize();
	const z = ref.sub(vD.copy(x).multiplyScalar(x.dot(ref))).normalize();
	const y = new THREE.Vector3().crossVectors(z, x);
	out.makeBasis(x, y, z).setPosition(vA);
	return cfg.stretch ? Math.max(0.2, len / ARM_REACH) : 1;
}

function partMatrix(part, d, f, out) {
	const s = socketAt(part, d, f, tmpC);
	const o = offsetAt(part, SEQS[seq].name, f);
	const off = new THREE.Matrix4().compose(new THREE.Vector3(...o.p), new THREE.Quaternion(...o.q), new THREE.Vector3(...o.s));
	const px = PX.clone().multiply(new THREE.Matrix4().makeScale(1, s, 1));
	return out.copy(tmpC).multiply(off).multiply(px);
}

function applyFrame() {
	const d = data;
	const f = Math.min(frame, SEQS[seq].frames - 1);
	// Chell's skin
	for (let b = 0; b < NB; b++) skinM[b].multiplyMatrices(boneMatrix(d, f, b, tmpA), poseToBone[b]);
	const n = meshPos.length / 3;
	for (let v = 0; v < n; v++) {
		const px = meshPos[v * 3], py = meshPos[v * 3 + 1], pz = meshPos[v * 3 + 2];
		let x = 0, y = 0, z = 0;
		for (let k = 0; k < 4; k++) {
			const w = skinW[v * 4 + k];
			if (!w) continue;
			const e = skinM[skinIdx[v * 4 + k]].elements;
			x += w * (e[0] * px + e[4] * py + e[8] * pz + e[12]);
			y += w * (e[1] * px + e[5] * py + e[9] * pz + e[13]);
			z += w * (e[2] * px + e[6] * py + e[10] * pz + e[14]);
		}
		chellPos[v * 3] = x;
		chellPos[v * 3 + 1] = y;
		chellPos[v * 3 + 2] = z;
	}
	chellGeo.attributes.position.needsUpdate = true;
	chellGeo.computeVertexNormals();
	if (bones.visible) {
		for (let b = 0; b < NB; b++) {
			const parent = body.bones[b].parent;
			vA.setFromMatrixPosition(boneMatrix(d, f, b, tmpA));
			vB.copy(vA);
			if (parent >= 0) vB.setFromMatrixPosition(boneMatrix(d, f, parent, tmpB));
			bonePos.set([vA.x, vA.y, vA.z, vB.x, vB.y, vB.z], b * 6);
		}
		boneGeo.attributes.position.needsUpdate = true;
	}
	// the arms
	for (const [key, p] of Object.entries(parts)) {
		const s = socketAt(key, d, f, p.socket.matrix);
		p.socket.matrixWorldNeedsUpdate = true;
		p.px.matrix.copy(PX).multiply(new THREE.Matrix4().makeScale(1, s, 1));
		p.px.matrixWorldNeedsUpdate = true;
		if (!(dragging && key === current)) {
			const o = offsetAt(key, SEQS[seq].name, f);
			p.offset.position.set(...o.p);
			p.offset.quaternion.set(...o.q);
			p.offset.scale.set(...o.s);
		}
		p.offset.visible = project.parts[key].visible || key === current;
	}
	// the eyes (and where you look from them: the ending lets the player turn the view a little)
	const eyesM = boneMatrix(d, f, eyes.bone, tmpA).multiply(eyesLocal);
	const look = new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(THREE.MathUtils.degToRad(lookPitch), THREE.MathUtils.degToRad(lookYaw), 0, 'YXZ'));
	cameraFP.matrix.copy(src.matrixWorld).multiply(eyesM).multiply(CAM).multiply(look);
	cameraFP.matrixWorldNeedsUpdate = true;
	vA.setFromMatrixPosition(eyesM).applyMatrix4(src.matrixWorld);
	if (!orbitTargetSet) {
		orbit.target.copy(vA);
		cameraOrbit.position.copy(vA).add(new THREE.Vector3(50, 25, 50));
		orbitTargetSet = true;
	}
	updateFields();
}
let orbitTargetSet = false;
let lookYaw = 0, lookPitch = 0;

// ---- gizmo ----
const gizmo = new TransformControls(activeCamera(), renderer.domElement);
gizmo.setSize(0.8);
gizmo.setSpace('local');
scene.add(gizmo);
let dragging = false;
gizmo.addEventListener('dragging-changed', (e) => {
	dragging = e.value;
	orbit.enabled = !e.value && !firstPerson;
	if (!e.value) applyFrame();
});
gizmo.addEventListener('objectChange', () => {
	if (!dragging) return;
	storeKey();
});
function storeKey(force = false) {
	if (!$('autokey').checked && !force) {
		status('Auto key is off: press K to keep this offset at frame ' + frame + '.');
		return;
	}
	const o = parts[current].offset;
	const k = { f: frame, p: o.position.toArray().map(r4), q: o.quaternion.toArray().map(r6), s: o.scale.toArray().map(r4) };
	const keys = keysOf(current, SEQS[seq].name);
	const i = keys.findIndex((x) => x.f === frame);
	if (i >= 0) keys[i] = k;
	else {
		keys.push(k);
		keys.sort((a, b) => a.f - b.f);
	}
	dirty = true;
	refreshKeys();
	updateFields();
}
const r4 = (x) => Math.round(x * 1e4) / 1e4, r6 = (x) => Math.round(x * 1e6) / 1e6;
function setGizmoMode(m) {
	gizmo.setMode(m);
	$('gMove').classList.toggle('on', m === 'translate');
	$('gRot').classList.toggle('on', m === 'rotate');
	$('gScale').classList.toggle('on', m === 'scale');
}

// ---- UI ----
SEQS.forEach((s, i) => {
	const label = `${s.name} (${s.frames > 1 ? (s.frames / s.fps).toFixed(1) + ' s' : 'pose'})`;
	$('seq').add(new Option(label, i));
	$('copyFrom').add(new Option(s.name, s.name));
});
body.bones.forEach((b) => $('bone').add(new Option(b.name, b.name)));
$('seq').value = seq;
$('slim').checked = !!project.slim;

function selectPart(key) {
	current = key;
	$('tabRight').classList.toggle('on', key === 'right');
	$('tabLeft').classList.toggle('on', key === 'left');
	gizmo.attach(parts[key].offset);
	const cfg = project.parts[key];
	$('visible').checked = cfg.visible;
	$('mode').value = cfg.mode;
	$('bone').value = cfg.bone || ARMS[key].wrist;
	$('stretch').checked = cfg.stretch;
	$('boneRow').style.display = cfg.mode === 'bone' ? '' : 'none';
	$('stretchRow').style.display = cfg.mode === 'aim' ? '' : 'none';
	refreshKeys();
	applyFrame();
}
function refreshKeys() {
	const keys = project.parts[current].keys[SEQS[seq].name] || [];
	const ul = $('keys');
	ul.innerHTML = '';
	if (!keys.length) {
		const li = document.createElement('li');
		li.textContent = 'none - no offset';
		li.style.color = 'var(--dim)';
		ul.appendChild(li);
	}
	for (const k of keys) {
		const li = document.createElement('li');
		li.textContent = 'frame ' + k.f;
		li.className = k.f === frame ? 'here' : '';
		li.onclick = () => setFrame(k.f);
		ul.appendChild(li);
	}
	// ticks on the timeline
	const strip = $('keytick');
	strip.innerHTML = '';
	const last = Math.max(1, SEQS[seq].frames - 1);
	for (const k of keys) {
		const t = document.createElement('div');
		t.className = 'tick';
		t.style.left = `calc(${(k.f / last) * 100}% - 1px)`;
		strip.appendChild(t);
	}
}
function updateFields() {
	const o = parts[current].offset;
	const e = new THREE.Euler().setFromQuaternion(o.quaternion, 'XYZ');
	const set = (id, v) => {
		if (document.activeElement !== $(id)) $(id).value = (Math.round(v * 100) / 100).toString();
	};
	set('px', o.position.x);
	set('py', o.position.y);
	set('pz', o.position.z);
	set('rx', THREE.MathUtils.radToDeg(e.x));
	set('ry', THREE.MathUtils.radToDeg(e.y));
	set('rz', THREE.MathUtils.radToDeg(e.z));
	set('sx', o.scale.x);
	set('sy', o.scale.y);
	set('sz', o.scale.z);
	const s = SEQS[seq];
	$('frameInfo').textContent = `${(frame / s.fps).toFixed(2)} s / ${(s.frames / s.fps).toFixed(2)} s`;
	if (document.activeElement !== $('frameNum')) $('frameNum').value = frame;
	$('frame').value = frame;
	document.querySelectorAll('#keys li').forEach((li) => li.classList.toggle('here', li.textContent === 'frame ' + frame));
}
function fieldsChanged() {
	const o = parts[current].offset;
	const num = (id, d) => {
		const v = parseFloat($(id).value);
		return Number.isFinite(v) ? v : d;
	};
	o.position.set(num('px', 0), num('py', 0), num('pz', 0));
	o.quaternion.setFromEuler(new THREE.Euler(...['rx', 'ry', 'rz'].map((id) => THREE.MathUtils.degToRad(num(id, 0))), 'XYZ'));
	o.scale.set(num('sx', 1), num('sy', 1), num('sz', 1));
	storeKey();
	applyFrame();
}
['px', 'py', 'pz', 'rx', 'ry', 'rz', 'sx', 'sy', 'sz'].forEach((id) => $(id).addEventListener('change', fieldsChanged));

async function setSeq(i) {
	seq = i;
	orbitTargetSet = false; // (each animation moves the body somewhere else)
	status('Loading ' + SEQS[i].name + '...');
	data = await seqData(i);
	status(SEQS[i].name + ': ' + SEQS[i].frames + ' frames at ' + SEQS[i].fps + ' fps.');
	$('frame').max = SEQS[i].frames - 1;
	$('frameNum').max = SEQS[i].frames - 1;
	setFrame(Math.min(frame, SEQS[i].frames - 1));
	refreshKeys();
}
function setFrame(f) {
	frame = Math.max(0, Math.min(SEQS[seq].frames - 1, Math.round(f)));
	playT = frame;
	applyFrame();
	refreshKeys();
}

$('seq').onchange = () => setSeq(parseInt($('seq').value));
$('frame').oninput = () => setFrame(parseInt($('frame').value));
$('frameNum').onchange = () => setFrame(parseInt($('frameNum').value) || 0);
$('play').onclick = () => togglePlay();
function togglePlay() {
	playing = !playing;
	$('play').innerHTML = playing ? '&#10074;&#10074;' : '&#9654;';
	playT = frame;
}
$('tabRight').onclick = () => selectPart('right');
$('tabLeft').onclick = () => selectPart('left');
$('visible').onchange = () => {
	project.parts[current].visible = $('visible').checked;
	dirty = true;
	applyFrame();
};
$('mode').onchange = () => {
	project.parts[current].mode = $('mode').value;
	if ($('mode').value === 'bone' && !project.parts[current].bone) project.parts[current].bone = $('bone').value;
	dirty = true;
	selectPart(current);
};
$('bone').onchange = () => {
	project.parts[current].bone = $('bone').value;
	dirty = true;
	applyFrame();
};
$('stretch').onchange = () => {
	project.parts[current].stretch = $('stretch').checked;
	dirty = true;
	applyFrame();
};
$('gMove').onclick = () => setGizmoMode('translate');
$('gRot').onclick = () => setGizmoMode('rotate');
$('gScale').onclick = () => setGizmoMode('scale');
$('gLocal').onchange = () => gizmo.setSpace($('gLocal').checked ? 'local' : 'world');
$('resetOff').onclick = () => {
	const o = parts[current].offset;
	o.position.set(0, 0, 0);
	o.quaternion.identity();
	o.scale.set(1, 1, 1);
	storeKey();
	applyFrame();
};
$('keyHere').onclick = () => storeKey(true);
$('delKey').onclick = () => deleteKey();
function deleteKey() {
	const keys = keysOf(current, SEQS[seq].name);
	const i = keys.findIndex((k) => k.f === frame);
	if (i < 0) return status('No key at frame ' + frame + '.');
	keys.splice(i, 1);
	dirty = true;
	refreshKeys();
	applyFrame();
}
$('prevKey').onclick = () => {
	const keys = keysOf(current, SEQS[seq].name).filter((k) => k.f < frame);
	if (keys.length) setFrame(keys[keys.length - 1].f);
};
$('nextKey').onclick = () => {
	const k = keysOf(current, SEQS[seq].name).find((k) => k.f > frame);
	if (k) setFrame(k.f);
};
$('copyKeys').onclick = () => {
	const from = $('copyFrom').value;
	const to = SEQS[seq].name;
	if (from === to) return;
	const frames = SEQS[seq].frames;
	project.parts[current].keys[to] = (project.parts[current].keys[from] || []).filter((k) => k.f < frames).map((k) => JSON.parse(JSON.stringify(k)));
	dirty = true;
	refreshKeys();
	applyFrame();
	status(`Copied the ${current} arm's keys from ${from}.`);
};
$('clearKeys').onclick = () => {
	if (!confirm(`Remove all of the ${current} arm's keys in ${SEQS[seq].name}?`)) return;
	project.parts[current].keys[SEQS[seq].name] = [];
	dirty = true;
	refreshKeys();
	applyFrame();
};
$('showChell').onchange = () => (chell.visible = $('showChell').checked);
$('chellAlpha').oninput = () => {
	chellMat.opacity = parseFloat($('chellAlpha').value);
	chellMat.depthWrite = chellMat.opacity >= 1;
	chellMat.transparent = chellMat.opacity < 1;
};
$('showBones').onchange = () => {
	bones.visible = $('showBones').checked;
	applyFrame();
};
$('fov').onchange = () => {
	cameraFP.fov = parseFloat($('fov').value) || 73.74;
	cameraFP.updateProjectionMatrix();
};
$('vFirst').onclick = () => setView(true);
$('vOrbit').onclick = () => setView(false);
function setView(fp) {
	firstPerson = fp;
	$('vFirst').classList.toggle('on', fp);
	$('vOrbit').classList.toggle('on', !fp);
	orbit.enabled = !fp;
	gizmo.camera = activeCamera();
	resize();
}
$('slim').onchange = async () => {
	project.slim = $('slim').checked;
	dirty = true;
	buildArms(project.slim);
	if (!customSkin) await defaultSkin();
	applyFrame();
};
let customSkin = false;
$('skinFile').onchange = async () => {
	const file = $('skinFile').files[0];
	if (!file) return;
	await loadSkin(URL.createObjectURL(file));
	customSkin = true;
	status('Skin: ' + file.name);
};
async function defaultSkin() {
	try {
		await loadSkin('/api/skin' + (project.slim ? '?slim=1' : ''));
	} catch (e) {
		// a placeholder: grey arms
		const c = document.createElement('canvas');
		c.width = c.height = 64;
		const g = c.getContext('2d');
		g.fillStyle = '#c69a7a';
		g.fillRect(0, 0, 64, 64);
		await loadSkin(c.toDataURL());
		status("No Minecraft jar found for Steve's skin: load your skin PNG.", true);
	}
}
$('save').onclick = () => save();
async function save() {
	try {
		const r = await (await api('/api/project', { method: 'POST', body: JSON.stringify(project, null, 1) })).json();
		dirty = false;
		status('Saved ' + r.saved);
	} catch (e) {
		status('Save failed: ' + e.message, true);
	}
}
$('export').onclick = () => exportToGame();
async function exportToGame() {
	try {
		const keep = seq;
		const out = { version: 1, model: body.model, slim: !!project.slim, parts: {}, sequences: [] };
		for (const k of ['right', 'left']) out.parts[k] = { visible: project.parts[k].visible };
		const m = new THREE.Matrix4();
		for (let i = 0; i < SEQS.length; i++) {
			status('Baking ' + SEQS[i].name + '...');
			const d = await seqData(i);
			seq = i; // (offsetAt reads the keys of the current animation)
			const entry = { name: SEQS[i].name, frames: SEQS[i].frames, fps: SEQS[i].fps };
			for (const k of ['right', 'left']) {
				const arr = [];
				for (let f = 0; f < SEQS[i].frames; f++) {
					partMatrix(k, d, f, m);
					const e = m.elements; // column-major
					arr.push(e[0], e[4], e[8], e[12], e[1], e[5], e[9], e[13], e[2], e[6], e[10], e[14]);
				}
				entry[k] = arr.map(r4);
			}
			out.sequences.push(entry);
		}
		seq = keep;
		data = await seqData(seq);
		await save();
		const r = await (await api('/api/export', { method: 'POST', body: JSON.stringify(out) })).json();
		status('Exported (' + Math.round(r.bytes / 1024) + ' KB) to:\n' + r.written.join('\n') + '\nMinecraft picks it up within a second (it reads the file again when it changes) - no restart needed.');
	} catch (e) {
		status('Export failed: ' + e.message, true);
	}
}
window.addEventListener('beforeunload', (e) => {
	if (dirty) e.preventDefault();
});
window.addEventListener('keydown', (e) => {
	if (e.target.tagName === 'INPUT' && e.target.type !== 'range' && e.target.type !== 'checkbox') return;
	if (e.key === 'w' || e.key === 'W') setGizmoMode('translate');
	else if (e.key === 'e' || e.key === 'E') setGizmoMode('rotate');
	else if (e.key === 'r' || e.key === 'R') setGizmoMode('scale');
	else if (e.key === ' ') {
		togglePlay();
		e.preventDefault();
	} else if (e.key === 'ArrowLeft') setFrame(frame - (e.shiftKey ? 10 : 1));
	else if (e.key === 'ArrowRight') setFrame(frame + (e.shiftKey ? 10 : 1));
	else if (e.key === 'k' || e.key === 'K') storeKey(true);
	else if (e.key === 'Delete') deleteKey();
	else if (e.key === 's' && e.ctrlKey) {
		save();
		e.preventDefault();
	}
});

// the key ticks sit over the timeline
const wrap = document.createElement('div');
wrap.style.cssText = 'position:relative;flex:1;display:flex;flex-direction:column;justify-content:center';
const slider = $('frame');
slider.replaceWith(wrap);
wrap.appendChild(slider);
slider.style.width = '100%';
const tickStrip = document.createElement('div');
tickStrip.id = 'keytick';
tickStrip.style.cssText = 'position:relative;height:6px;margin:0 8px';
wrap.appendChild(tickStrip);

function resize() {
	const w = view.clientWidth, h = view.clientHeight;
	renderer.setSize(w, h, false);
	for (const c of [cameraFP, cameraOrbit]) {
		c.aspect = w / h;
		c.updateProjectionMatrix();
	}
}
window.addEventListener('resize', resize);

// first person: drag on empty space to look around (from Chell's eyes), double-click to look ahead again
let looking = null;
renderer.domElement.addEventListener('pointerdown', (e) => {
	if (!firstPerson || gizmo.axis !== null || e.button !== 0) return;
	looking = { x: e.clientX, y: e.clientY, yaw: lookYaw, pitch: lookPitch };
	renderer.domElement.setPointerCapture(e.pointerId);
});
renderer.domElement.addEventListener('pointermove', (e) => {
	if (!looking) return;
	lookYaw = looking.yaw - (e.clientX - looking.x) * 0.25;
	lookPitch = Math.max(-89, Math.min(89, looking.pitch - (e.clientY - looking.y) * 0.25));
	applyFrame();
});
renderer.domElement.addEventListener('pointerup', () => (looking = null));
renderer.domElement.addEventListener('dblclick', () => {
	if (!firstPerson) return;
	lookYaw = lookPitch = 0;
	applyFrame();
});

// (for the browser console)
window.endingArms = { THREE, scene, src, cameraFP, cameraOrbit, parts, chell, get frame() { return frame; }, get seq() { return seq; } };

// ---- go ----
buildArms(project.slim);
await defaultSkin();
await setSeq(seq);
selectPart('right');
setGizmoMode('translate');
setView(true);
status(SEQS[seq].name + ' - pose the arms; Export puts them in the game.');
let last = performance.now();
renderer.setAnimationLoop((now) => {
	const dt = Math.min(0.1, (now - last) / 1000);
	last = now;
	if (playing) {
		const s = SEQS[seq];
		playT += dt * s.fps * parseFloat($('speed').value);
		if (playT > s.frames - 1) playT = s.loop || s.frames < 2 ? 0 : 0;
		const f = Math.floor(playT);
		if (f !== frame) {
			frame = f;
			applyFrame();
		}
	}
	if (!firstPerson) orbit.update();
	renderer.render(scene, activeCamera());
});
