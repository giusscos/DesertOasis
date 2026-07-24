#pragma once
#include <stdint.h>

// C interface for Swift — all functions use extern "C" so Swift can call them
// via the bridging header with no name-mangling surprises.

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// World generation
// ---------------------------------------------------------------------------

/// Computes the surface block height for one column (same formula used inside
/// voxel_gen_chunk — exposed so Swift can keep columnHeight() / surfaceY() working).
int32_t voxel_gen_column_height(int32_t bx, int32_t bz,
                                uint64_t seed,
                                float total_size, float block_size,
                                int32_t height_scale, int32_t base_height);

/// Fills out_blocks[16 × 48 × 16] with VoxelType raw values.
/// Index layout matches VoxelChunk: i = lx + 16*(lz + 16*ly).
/// camp_wx/wz/wr: world-space positions and pad radii of each camp site.
/// camp_pad_h: precomputed average surface height (block units) for each camp.
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
                     int32_t        camp_count);

// ---------------------------------------------------------------------------
// Mesh building
// ---------------------------------------------------------------------------

/// Builds a triangle mesh for one voxel chunk.
///
/// padded_blocks is an (16+2) × 48 × (16+2) = 18×48×18 array that holds the
/// chunk's blocks plus a 1-block border from neighbouring chunks.
/// Index layout: pi = (lx+1) + 18*((lz+1) + 18*ly)  for lx,lz ∈ [-1..16].
///
/// Allocates out_vertices, out_normals, out_colors, out_indices on the heap.
/// Returns the vertex count (0 = empty chunk, outputs are null).
/// Caller must free with voxel_mesh_free().
int32_t voxel_mesh_build(const uint8_t* padded_blocks,
                         float          block_size,
                         float**        out_vertices,   // xyz  × vertex_count
                         float**        out_normals,    // xyz  × vertex_count
                         float**        out_colors,     // rgba × vertex_count
                         int32_t**      out_indices,
                         int32_t*       out_vertex_count,
                         int32_t*       out_index_count);

void voxel_mesh_free(float*   vertices,
                     float*   normals,
                     float*   colors,
                     int32_t* indices);

#ifdef __cplusplus
} // extern "C"
#endif
