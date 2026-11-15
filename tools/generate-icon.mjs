// Generates a clean 64x64 RGBA PNG icon for Flik Connector.
import fs from 'fs';
import path from 'path';
import zlib from 'zlib';

function createPng(width, height, getPixel) {
  const rowSize = width * 4 + 1;
  const rawData = Buffer.alloc(rowSize * height);

  for (let y = 0; y < height; y++) {
    const rowOffset = y * rowSize;
    rawData[rowOffset] = 0; // Filter type None
    for (let x = 0; x < width; x++) {
      const [r, g, b, a] = getPixel(x, y);
      const pxOffset = rowOffset + 1 + x * 4;
      rawData[pxOffset] = r;
      rawData[pxOffset + 1] = g;
      rawData[pxOffset + 2] = b;
      rawData[pxOffset + 3] = a;
    }
  }

  const deflated = zlib.deflateSync(rawData);

  // PNG Header
  const header = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

  // IHDR
  const ihdr = Buffer.alloc(25);
  ihdr.writeUInt32BE(13, 0);
  ihdr.write('IHDR', 4);
  ihdr.writeUInt32BE(width, 8);
  ihdr.writeUInt32BE(height, 12);
  ihdr[16] = 8; // Bit depth
  ihdr[17] = 6; // RGBA
  ihdr[18] = 0; // Compression
  ihdr[19] = 0; // Filter
  ihdr[20] = 0; // Interlace
  ihdr.writeUInt32BE(crc32(ihdr.subarray(4, 21)), 21);

  // IDAT
  const idat = Buffer.alloc(8 + deflated.length + 4);
  idat.writeUInt32BE(deflated.length, 0);
  idat.write('IDAT', 4);
  deflated.copy(idat, 8);
  idat.writeUInt32BE(crc32(idat.subarray(4, 8 + deflated.length)), 8 + deflated.length);

  // IEND
  const iend = Buffer.from([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

  return Buffer.concat([header, ihdr, idat, iend]);
}

function crc32(buf) {
  let crc = -1;
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ table[(crc ^ buf[i]) & 0xff];
  }
  return (crc ^ -1) >>> 0;
}

const table = new Int32Array(256);
for (let i = 0; i < 256; i++) {
  let c = i;
  for (let k = 0; k < 8; k++) {
    c = (c & 1) ? (-306674912 ^ (c >>> 1)) : (c >>> 1);
  }
  table[i] = c;
}

// Draw Flik icon: blue circle with bold white "F" (256x256)
const size = 256;
const pngBuf = createPng(size, size, (x, y) => {
  const dx = x - size / 2;
  const dy = y - size / 2;
  const dist = Math.sqrt(dx * dx + dy * dy);

  // Circle background #3566EF
  if (dist <= size / 2 - 4) {
    // Draw "F" in center (scaled 4x)
    // Vertical stem of F: x from 88 to 116, y from 64 to 192
    const inStem = x >= 88 && x <= 116 && y >= 64 && y <= 192;
    // Top bar of F: x from 88 to 176, y from 64 to 92
    const inTopBar = x >= 88 && x <= 176 && y >= 64 && y <= 92;
    // Middle bar of F: x from 88 to 156, y from 116 to 140
    const inMidBar = x >= 88 && x <= 156 && y >= 116 && y <= 140;

    if (inStem || inTopBar || inMidBar) {
      return [255, 255, 255, 255]; // White letter F
    }
    return [53, 102, 239, 255]; // Blue background
  }
  return [0, 0, 0, 0]; // Transparent
});

const outPath = path.resolve('windows/build/icon.png');
fs.writeFileSync(outPath, pngBuf);
console.log('Generated Flik icon at:', outPath);
