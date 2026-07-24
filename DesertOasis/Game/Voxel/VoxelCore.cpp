#include "VoxelCore.hpp"
#include <cmath>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <algorithm>

// ============================================================
// Noise
// ============================================================

static float noise_hash(int x, int y, uint64_t seed) {
    // Matches Swift's VoxelNoise.hash — wrapping arithmetic throughout.
    int64_t lin = (int64_t)x * 1619LL + (int64_t)y * 31337LL;
    uint64_t n  = (uint64_t)lin + seed * 1000003ULL;
    n ^= (n >> 16);
    n *= 0x45d9f3bULL;
    n ^= (n >> 16);
    return (float)(n & 0xFFFFFFULL) / (float)0xFFFFFFULL;
}

static float smoothstep(float t) { return t * t * (3.f - 2.f * t); }

static float value_noise(float x, float y, uint64_t seed) {
    int   xi = (int)floorf(x), yi = (int)floorf(y);
    float xf = x - floorf(x),  yf = y - floorf(y);
    float v00 = noise_hash(xi,   yi,   seed);
    float v10 = noise_hash(xi+1, yi,   seed);
    float v01 = noise_hash(xi,   yi+1, seed);
    float v11 = noise_hash(xi+1, yi+1, seed);
    float ux  = smoothstep(xf), uy = smoothstep(yf);
    return (v00*(1.f-ux) + v10*ux) * (1.f-uy) + (v01*(1.f-ux) + v11*ux) * uy;
}

static float fbm(float x, float y, uint64_t seed, int octaves = 3) {
    float val = 0.f, amp = 0.5f, freq = 1.f;
    for (int o = 0; o < octaves; ++o) {
        val  += value_noise(x*freq, y*freq, seed + (uint64_t)(o * 7919)) * amp;
        amp  *= 0.5f;
        freq *= 2.f;
    }
    return val;
}

// ============================================================
// World generation
// ============================================================

static inline int clamp_height(int h) {
    return h < 2 ? 2 : (h > 46 ? 46 : h); // VoxelChunk.sizeY - 2 = 46
}

int32_t voxel_gen_column_height(int32_t bx, int32_t bz,
                                uint64_t seed,
                                float total_size, float block_size,
                                int32_t height_scale, int32_t base_height) {
    // Matches Swift's VoxelWorldGenerator.columnHeight()
    float nx = (float)bx / total_size * 4.f * block_size;
    float nz = (float)bz / total_size * 4.f * block_size;
    float h  = fbm(nx, nz, seed) * (float)height_scale + (float)base_height;
    return (int32_t)clamp_height((int)roundf(h));
}

void voxel_gen_chunk(uint8_t*       out_blocks,
                     int32_t        cx,
                     int32_t        cz,
                     uint64_t       seed,
                     float          block_size,
                     float          total_size,
                     int32_t        height_scale,
                     int32_t        base_height,
                     const float*   camp_wx,
                     const float*   camp_wz,
                     const float*   camp_wr,
                     const int32_t* camp_pad_h,
                     int32_t        camp_count) {
    const int SX = 16, SY = 48, SZ = 16;
    const int baseBX = cx * SX, baseBZ = cz * SZ;

    int sand_d = std::max(1, (int)roundf(2.f / block_size));
    int ss_d   = std::max(1, (int)roundf(3.f / block_size));
    float blend = (float)std::max(4, (int)roundf(14.f / block_size));

    memset(out_blocks, 0, (size_t)(SX * SY * SZ));

    for (int lz = 0; lz < SZ; ++lz) {
        for (int lx = 0; lx < SX; ++lx) {
            int bx = baseBX + lx;
            int bz = baseBZ + lz;

            int h = (int)voxel_gen_column_height(
                bx, bz, seed, total_size, block_size, height_scale, base_height);

            // Camp-pad blending (matches Swift's generateChunk exactly)
            for (int ci = 0; ci < camp_count; ++ci) {
                float sbx  = camp_wx[ci] / block_size;
                float sbz  = camp_wz[ci] / block_size;
                float dx   = (float)bx - sbx;
                float dz   = (float)bz - sbz;
                float dist = sqrtf(dx*dx + dz*dz);
                float cr   = camp_wr[ci] / block_size;
                int   padH = (int)camp_pad_h[ci];

                if (dist <= cr) {
                    h = padH;
                    break;
                } else if (dist < cr + blend) {
                    float t  = (dist - cr) / blend;
                    float s  = t * t * (3.f - 2.f * t);
                    float hf = (float)padH * (1.f - s) + (float)h * s;
                    h = clamp_height((int)roundf(hf));
                }
            }

            // Fill column (air already set by memset)
            for (int by = 0; by < h; ++by) {
                uint8_t type;
                if      (by >= h - sand_d)          type = 1; // sand
                else if (by >= h - sand_d - ss_d)   type = 2; // sandstone
                else                                 type = 3; // rock
                out_blocks[lx + SX * (lz + SZ * by)] = type;
            }
        }
    }
}

// ============================================================
// Block type helpers
// ============================================================

static inline bool is_transparent(uint8_t t) {
    return t == 0 || t == 4 || t == 7; // air | water | leaf
}

static inline bool should_emit(uint8_t type, uint8_t nbr) {
    if (type == 4)        return nbr != 4;           // water: not facing water
    if (type == 7)        return nbr == 0 || nbr == 4; // leaf: only vs air/water
    return is_transparent(nbr);
}

// ============================================================
// Colours per VoxelType raw value (matches VoxelType.swift .color)
// ============================================================

struct RGBA { float r, g, b, a; };

static const RGBA BLOCK_COLOR[15] = {
    {0.f,    0.f,    0.f,    0.f   }, // 0  air
    {0.87f,  0.78f,  0.57f,  1.f   }, // 1  sand
    {0.78f,  0.66f,  0.48f,  1.f   }, // 2  sandstone
    {0.55f,  0.48f,  0.42f,  1.f   }, // 3  rock
    {0.22f,  0.55f,  0.78f,  0.72f }, // 4  water
    {0.28f,  0.55f,  0.28f,  1.f   }, // 5  cactus
    {0.50f,  0.36f,  0.20f,  1.f   }, // 6  wood
    {0.25f,  0.48f,  0.22f,  0.85f }, // 7  leaf
    {0.72f,  0.62f,  0.42f,  1.f   }, // 8  canvas
    {0.55f,  0.35f,  0.25f,  1.f   }, // 9  cloth
    {0.30f,  0.20f,  0.12f,  1.f   }, // 10 darkWood
    {0.32f,  0.32f,  0.32f,  1.f   }, // 11 iron
    {0.72f,  0.55f,  0.22f,  1.f   }, // 12 brass
    {0.90f,  0.74f,  0.58f,  1.f   }, // 13 skin
    {0.25f,  0.18f,  0.12f,  1.f   }, // 14 hair
};

// ============================================================
// Face table (matches VoxelMesher.swift face order and winding)
// ============================================================

struct FaceDef {
    int8_t  dx, dy, dz;          // neighbour direction
    float   nx, ny, nz;          // normal
    float   corners[4][3];       // 4 corners, offsets from block min corner
};

static const FaceDef FACES[6] = {
    // +Y top
    { 0, 1, 0,   0,1,0,  {{0,1,0},{0,1,1},{1,1,1},{1,1,0}} },
    // -Y bottom
    { 0,-1, 0,   0,-1,0, {{0,0,0},{1,0,0},{1,0,1},{0,0,1}} },
    // +X right
    { 1, 0, 0,   1,0,0,  {{1,0,0},{1,1,0},{1,1,1},{1,0,1}} },
    // -X left
    {-1, 0, 0,  -1,0,0,  {{0,0,0},{0,0,1},{0,1,1},{0,1,0}} },
    // +Z front
    { 0, 0, 1,   0,0,1,  {{0,0,1},{1,0,1},{1,1,1},{0,1,1}} },
    // -Z back
    { 0, 0,-1,   0,0,-1, {{0,0,0},{0,1,0},{1,1,0},{1,0,0}} },
};

// ============================================================
// Mesh builder
// ============================================================

int32_t voxel_mesh_build(const uint8_t* padded,
                         float          bs,
                         float**        out_verts,
                         float**        out_norms,
                         float**        out_cols,
                         int32_t**      out_idx,
                         int32_t*       out_vc,
                         int32_t*       out_ic) {
    const int SX = 16, SY = 48, SZ = 16;
    const int PX = 18, PZ = 18; // padded width/depth

    std::vector<float>   verts, norms, cols;
    std::vector<int32_t> indices;
    verts.reserve(8192);
    norms.reserve(8192);
    cols.reserve(8192);
    indices.reserve(12288);

    for (int ly = 0; ly < SY; ++ly) {
        for (int lz = 0; lz < SZ; ++lz) {
            for (int lx = 0; lx < SX; ++lx) {
                // Padded index for this block (inner cell)
                int pi   = (lx+1) + PX * ((lz+1) + PZ * ly);
                uint8_t  type = padded[pi];
                // Skip air and water — oasis water is drawn by OasisWaterNode.
                // Meshing translucent water into opaque sand chunks punches square holes.
                if (type == 0 || type == 4) continue;

                RGBA col = (type < 15) ? BLOCK_COLOR[type] : BLOCK_COLOR[0];
                float ox = (float)lx * bs;
                float oy = (float)ly * bs;
                float oz = (float)lz * bs;

                for (int fi = 0; fi < 6; ++fi) {
                    const FaceDef& f = FACES[fi];
                    int nlx = lx + (int)f.dx;
                    int nly = ly + (int)f.dy;
                    int nlz = lz + (int)f.dz;

                    uint8_t nbr;
                    if (nly < 0 || nly >= SY) {
                        nbr = 0; // treat out-of-Y as air
                    } else {
                        // nlx ∈ [-1,16], nlz ∈ [-1,16] — all within padded bounds
                        nbr = padded[(nlx+1) + PX * ((nlz+1) + PZ * nly)];
                    }

                    if (!should_emit(type, nbr)) continue;

                    int32_t base = (int32_t)(verts.size() / 3);

                    for (int ci = 0; ci < 4; ++ci) {
                        verts.push_back(ox + f.corners[ci][0] * bs);
                        verts.push_back(oy + f.corners[ci][1] * bs);
                        verts.push_back(oz + f.corners[ci][2] * bs);
                        norms.push_back(f.nx);
                        norms.push_back(f.ny);
                        norms.push_back(f.nz);
                        cols.push_back(col.r);
                        cols.push_back(col.g);
                        cols.push_back(col.b);
                        cols.push_back(col.a);
                    }
                    indices.push_back(base);     indices.push_back(base+1);
                    indices.push_back(base+2);   indices.push_back(base);
                    indices.push_back(base+2);   indices.push_back(base+3);
                }
            }
        }
    }

    if (indices.empty()) {
        *out_verts = nullptr; *out_norms = nullptr;
        *out_cols  = nullptr; *out_idx   = nullptr;
        *out_vc = 0;          *out_ic = 0;
        return 0;
    }

    int32_t vc = (int32_t)(verts.size() / 3);
    int32_t ic = (int32_t)indices.size();

    float*   fv = new float[verts.size()];
    float*   fn = new float[norms.size()];
    float*   fc = new float[cols.size()];
    int32_t* fi = new int32_t[indices.size()];

    memcpy(fv, verts.data(),   verts.size()   * sizeof(float));
    memcpy(fn, norms.data(),   norms.size()   * sizeof(float));
    memcpy(fc, cols.data(),    cols.size()    * sizeof(float));
    memcpy(fi, indices.data(), indices.size() * sizeof(int32_t));

    *out_verts = fv; *out_norms = fn;
    *out_cols  = fc; *out_idx   = fi;
    *out_vc    = vc; *out_ic    = ic;
    return vc;
}

void voxel_mesh_free(float* v, float* n, float* c, int32_t* i) {
    delete[] v;
    delete[] n;
    delete[] c;
    delete[] i;
}
