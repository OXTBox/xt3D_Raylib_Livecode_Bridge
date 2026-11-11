/* xt3d_shim.c - flat C interface between LiveCode Builder and raylib.
 *
 * LiveCode Builder binds comfortably to functions that take numbers and C strings.
 * raylib passes structs by value. This file sits between the two:
 *   - math structs (Vector3, Color, Rectangle, Matrix...) are spread into numbers
 *   - resource structs (Image, Texture, Model, Sound, Camera...) live in tables
 *     here and are referred to by positive integer handles; 0 is "invalid"
 *   - struct and text results are written to a result buffer (see xt_set);
 *     the Builder library turns that into a LiveCode string
 *
 * xt3d_generated.inc holds one wrapper per raylib function and is produced by
 * gen_xt3d.py from raylib.h. The helpers below cover what raylib exposes only
 * through struct fields or pointers.
 *
 * Build (Windows, MinGW-w64, raylib built as a static library):
 *   gcc -O2 -shared -o xt3d.dll xt3d_shim.c -DXT3D_BUILD -I<raylib>/include \
 *       -L<raylib>/lib -lraylib -lopengl32 -lgdi32 -lwinmm
 * Build (macOS):
 *   clang -O2 -dynamiclib -o libxt3d.dylib xt3d_shim.c -I<raylib>/include <raylib>/lib/libraylib.a \
 *       -framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo
 * Build (Linux):
 *   gcc -O2 -shared -fPIC -o libxt3d.so xt3d_shim.c -I<raylib>/include -L<raylib>/lib -lraylib -lm -lpthread -ldl
 *
 * All calls must come from the thread that called xt3d_InitWindow.
 */
#include "raylib.h"
#include "rlgl.h"      /* low-level render state: culling, wire mode, depth test */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#if defined(_WIN32)
  #define XT3D_API __declspec(dllexport)
#else
  #define XT3D_API __attribute__((visibility("default")))
#endif

#define XT3D_VERSION "0.1.0"

/* ---------------------------------------------------------------- strings */

/* Text results never cross into LiveCode as C strings: LiveCode Builder frees a
 * returned string, which crashes on memory it does not own. Instead every
 * text-returning function writes into this buffer and returns the length; the
 * Builder library then reads it a byte at a time with xt3d_ResultByte. */
#define XT_RESULT_MAX 8192
static char xt_result[XT_RESULT_MAX];
static int  xt_result_len = 0;

static int xt_set(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    int n = vsnprintf(xt_result, XT_RESULT_MAX, fmt, ap);
    va_end(ap);
    if (n < 0) n = 0;
    if (n >= XT_RESULT_MAX) n = XT_RESULT_MAX - 1;
    xt_result_len = n;
    return n;
}

static const char *xt_str(const char *s) { return s ? s : ""; }

static Matrix xt_matrix(float m0, float m1, float m2, float m3, float m4, float m5, float m6, float m7,
                        float m8, float m9, float m10, float m11, float m12, float m13, float m14, float m15)
{
    Matrix m;
    m.m0 = m0; m.m1 = m1; m.m2 = m2; m.m3 = m3; m.m4 = m4; m.m5 = m5; m.m6 = m6; m.m7 = m7;
    m.m8 = m8; m.m9 = m9; m.m10 = m10; m.m11 = m11; m.m12 = m12; m.m13 = m13; m.m14 = m14; m.m15 = m15;
    return m;
}

/* ---------------------------------------------------------- handle tables */

/* One growable table per resource type. Slot 0 is a zeroed dummy so that an
 * invalid handle reaches raylib as an empty struct instead of a wild pointer. */
#define XT_TABLE(T) \
    static T   *xt_tab_##T = NULL; \
    static char *xt_use_##T = NULL; \
    static int   xt_cap_##T = 0; \
    static void xt_grow_##T(int want) { \
        if (want <= xt_cap_##T) return; \
        int cap = xt_cap_##T ? xt_cap_##T * 2 : 64; \
        while (cap < want) cap *= 2; \
        xt_tab_##T = (T *)realloc(xt_tab_##T, sizeof(T) * (size_t)cap); \
        xt_use_##T = (char *)realloc(xt_use_##T, (size_t)cap); \
        memset(xt_tab_##T + xt_cap_##T, 0, sizeof(T) * (size_t)(cap - xt_cap_##T)); \
        memset(xt_use_##T + xt_cap_##T, 0, (size_t)(cap - xt_cap_##T)); \
        xt_cap_##T = cap; \
    } \
    static T *xt_##T(int h) { \
        if (xt_cap_##T == 0) xt_grow_##T(64); \
        if (h <= 0 || h >= xt_cap_##T || !xt_use_##T[h]) { memset(&xt_tab_##T[0], 0, sizeof(T)); return &xt_tab_##T[0]; } \
        return &xt_tab_##T[h]; \
    } \
    static int xt_new_##T(T v) { \
        if (xt_cap_##T == 0) xt_grow_##T(64); \
        int h; \
        for (h = 1; h < xt_cap_##T; h++) if (!xt_use_##T[h]) break; \
        if (h == xt_cap_##T) xt_grow_##T(h + 1); \
        xt_tab_##T[h] = v; xt_use_##T[h] = 1; \
        return h; \
    } \
    static void xt_free_##T(int h) { \
        if (h > 0 && h < xt_cap_##T) { xt_use_##T[h] = 0; memset(&xt_tab_##T[h], 0, sizeof(T)); } \
    } \
    static int xt_count_##T(void) { \
        int n = 0; for (int h = 1; h < xt_cap_##T; h++) n += xt_use_##T[h]; return n; \
    }

XT_TABLE(Image)
XT_TABLE(Texture)
XT_TABLE(RenderTexture)
XT_TABLE(Font)
XT_TABLE(Mesh)
XT_TABLE(Shader)
XT_TABLE(Material)
XT_TABLE(Model)
XT_TABLE(ModelAnimation)
XT_TABLE(Wave)
XT_TABLE(Sound)
XT_TABLE(Music)
XT_TABLE(AudioStream)
XT_TABLE(Camera3D)
XT_TABLE(Camera2D)

XT3D_API int xt3d_ResultLength(void) { return xt_result_len; }
XT3D_API int xt3d_ResultByte(int index)
{
    return (index >= 0 && index < xt_result_len) ? (int)(unsigned char)xt_result[index] : 0;
}

/* ------------------------------------------------- generated raylib wrappers */

#include "xt3d_generated.inc"

/* ------------------------------------------------------------------ helpers */

XT3D_API int xt3d_Version(void)
{
    return xt_set("xt3d %s / raylib %s", XT3D_VERSION, RAYLIB_VERSION);
}

XT3D_API void xt3d_InitHidden(int width, int height, const char *title)
{
    if (IsWindowReady()) return;   /* a second InitWindow would orphan every GPU resource */
    SetConfigFlags(FLAG_WINDOW_HIDDEN);
    InitWindow(width, height, title);
}

/* --- cameras */

static Camera3D xt_cam3(float px, float py, float pz, float tx, float ty, float tz,
                        float ux, float uy, float uz, float fovy, int projection)
{
    Camera3D c;
    c.position = (Vector3){px, py, pz};
    c.target   = (Vector3){tx, ty, tz};
    c.up       = (Vector3){ux, uy, uz};
    c.fovy = fovy; c.projection = projection;
    return c;
}

XT3D_API int xt3d_CameraCreate(float px, float py, float pz, float tx, float ty, float tz,
                               float ux, float uy, float uz, float fovy, int projection)
{
    return xt_new_Camera3D(xt_cam3(px, py, pz, tx, ty, tz, ux, uy, uz, fovy, projection));
}

XT3D_API void xt3d_CameraSet(int camera, float px, float py, float pz, float tx, float ty, float tz,
                             float ux, float uy, float uz, float fovy, int projection)
{
    if (camera > 0 && camera < xt_cap_Camera3D && xt_use_Camera3D[camera])
        xt_tab_Camera3D[camera] = xt_cam3(px, py, pz, tx, ty, tz, ux, uy, uz, fovy, projection);
}

XT3D_API int xt3d_CameraGet(int camera)
{
    Camera3D *c = xt_Camera3D(camera);
    return xt_set("%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%d",
        (double)c->position.x, (double)c->position.y, (double)c->position.z,
        (double)c->target.x, (double)c->target.y, (double)c->target.z,
        (double)c->up.x, (double)c->up.y, (double)c->up.z, (double)c->fovy, c->projection);
}

XT3D_API void xt3d_CameraFree(int camera) { xt_free_Camera3D(camera); }

XT3D_API int xt3d_Camera2DCreate(float offsetX, float offsetY, float targetX, float targetY, float rotation, float zoom)
{
    Camera2D c; c.offset = (Vector2){offsetX, offsetY}; c.target = (Vector2){targetX, targetY};
    c.rotation = rotation; c.zoom = zoom;
    return xt_new_Camera2D(c);
}

XT3D_API void xt3d_Camera2DSet(int camera, float offsetX, float offsetY, float targetX, float targetY, float rotation, float zoom)
{
    if (camera > 0 && camera < xt_cap_Camera2D && xt_use_Camera2D[camera]) {
        Camera2D *c = &xt_tab_Camera2D[camera];
        c->offset = (Vector2){offsetX, offsetY}; c->target = (Vector2){targetX, targetY};
        c->rotation = rotation; c->zoom = zoom;
    }
}

XT3D_API void xt3d_Camera2DFree(int camera) { xt_free_Camera2D(camera); }

/* --- struct fields */

XT3D_API int xt3d_ImageInfo(int image)
{
    Image *i = xt_Image(image);
    return xt_set("%d,%d,%d,%d", i->width, i->height, i->mipmaps, i->format);
}

XT3D_API int xt3d_TextureInfo(int texture)
{
    Texture *t = xt_Texture(texture);
    return xt_set("%u,%d,%d,%d,%d", t->id, t->width, t->height, t->mipmaps, t->format);
}

XT3D_API int xt3d_RenderTextureGetTexture(int target)
{
    return xt_new_Texture(xt_RenderTexture(target)->texture);
}

XT3D_API int xt3d_ModelInfo(int model)
{
    Model *m = xt_Model(model);
    return xt_set("%d,%d,%u", m->meshCount, m->materialCount, m->skeleton.boneCount);
}

XT3D_API int xt3d_ModelGetMesh(int model, int index)
{
    Model *m = xt_Model(model);
    if (index < 0 || index >= m->meshCount) return 0;
    return xt_new_Mesh(m->meshes[index]);
}

XT3D_API void xt3d_ModelSetTransform(int model, float m0, float m1, float m2, float m3, float m4, float m5, float m6, float m7,
                                     float m8, float m9, float m10, float m11, float m12, float m13, float m14, float m15)
{
    xt_Model(model)->transform = xt_matrix(m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15);
}

XT3D_API int xt3d_ModelGetTransform(int model)
{
    Matrix r = xt_Model(model)->transform;
    return xt_set("%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g",
        (double)r.m0, (double)r.m1, (double)r.m2, (double)r.m3, (double)r.m4, (double)r.m5, (double)r.m6, (double)r.m7,
        (double)r.m8, (double)r.m9, (double)r.m10, (double)r.m11, (double)r.m12, (double)r.m13, (double)r.m14, (double)r.m15);
}

static Material *xt_model_material(int model, int material)
{
    Model *m = xt_Model(model);
    if (material < 0 || material >= m->materialCount || !m->materials) return NULL;
    return &m->materials[material];
}

XT3D_API void xt3d_ModelSetMaterialTexture(int model, int material, int mapType, int texture)
{
    Material *mat = xt_model_material(model, material);
    if (mat && mat->maps) SetMaterialTexture(mat, mapType, *xt_Texture(texture));
}

XT3D_API void xt3d_ModelSetMaterialColor(int model, int material, int mapType, int r, int g, int b, int a)
{
    Material *mat = xt_model_material(model, material);
    if (mat && mat->maps && mapType >= 0 && mapType <= MATERIAL_MAP_BRDF)
        mat->maps[mapType].color = (Color){(unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a};
}

XT3D_API void xt3d_ModelSetMaterialShader(int model, int material, int shader)
{
    Material *mat = xt_model_material(model, material);
    if (mat) mat->shader = *xt_Shader(shader);
}

XT3D_API void xt3d_MaterialSetColor(int material, int mapType, int r, int g, int b, int a)
{
    Material *mat = xt_Material(material);
    if (mat->maps && mapType >= 0 && mapType <= MATERIAL_MAP_BRDF)
        mat->maps[mapType].color = (Color){(unsigned char)r, (unsigned char)g, (unsigned char)b, (unsigned char)a};
}

XT3D_API void xt3d_MaterialSetShader(int material, int shader)
{
    xt_Material(material)->shader = *xt_Shader(shader);
}

/* --- animation sets */

#define XT_MAX_ANIMSETS 256
static struct { ModelAnimation *anims; int count; int first; } xt_animsets[XT_MAX_ANIMSETS];

XT3D_API int xt3d_LoadModelAnimations(const char *fileName)
{
    int count = 0;
    ModelAnimation *anims = LoadModelAnimations(fileName, &count);
    if (!anims || count <= 0) return xt_set("0,0");
    int slot = -1;
    for (int i = 0; i < XT_MAX_ANIMSETS; i++) if (!xt_animsets[i].anims) { slot = i; break; }
    if (slot < 0) { UnloadModelAnimations(anims, count); return xt_set("0,0"); }
    /* handles must be consecutive: find a free run of `count` slots */
    if (xt_cap_ModelAnimation == 0) xt_grow_ModelAnimation(64);
    int first = 1;
    for (;;) {
        xt_grow_ModelAnimation(first + count);
        int ok = 1;
        for (int k = 0; k < count; k++) if (xt_use_ModelAnimation[first + k]) { first = first + k + 1; ok = 0; break; }
        if (ok) break;
    }
    for (int k = 0; k < count; k++) { xt_tab_ModelAnimation[first + k] = anims[k]; xt_use_ModelAnimation[first + k] = 1; }
    xt_animsets[slot].anims = anims; xt_animsets[slot].count = count; xt_animsets[slot].first = first;
    return xt_set("%d,%d", first, count);
}

XT3D_API void xt3d_UnloadModelAnimations(int firstHandle)
{
    for (int i = 0; i < XT_MAX_ANIMSETS; i++) {
        if (xt_animsets[i].anims && xt_animsets[i].first == firstHandle) {
            for (int k = 0; k < xt_animsets[i].count; k++) xt_free_ModelAnimation(firstHandle + k);
            UnloadModelAnimations(xt_animsets[i].anims, xt_animsets[i].count);
            xt_animsets[i].anims = NULL; xt_animsets[i].count = 0; xt_animsets[i].first = 0;
            return;
        }
    }
}

XT3D_API int xt3d_ModelAnimationInfo(int anim)
{
    ModelAnimation *a = xt_ModelAnimation(anim);
    char name[33]; memcpy(name, a->name, 32); name[32] = 0;
    return xt_set("%s,%u,%d", name, a->boneCount, a->keyframeCount);
}

/* --- shader uniforms */

XT3D_API void xt3d_SetShaderValueFloats(int shader, int locIndex, int count, float a, float b, float c, float d)
{
    if (!IsWindowReady()) return;   /* no window yet: no GPU to talk to */
    float v[4] = {a, b, c, d};
    if (count < 1) count = 1;
    if (count > 4) count = 4;
    SetShaderValue(*xt_Shader(shader), locIndex, v, SHADER_UNIFORM_FLOAT + (count - 1));
}

XT3D_API void xt3d_SetShaderValueInt(int shader, int locIndex, int value)
{
    if (!IsWindowReady()) return;   /* no window yet: no GPU to talk to */
    SetShaderValue(*xt_Shader(shader), locIndex, &value, SHADER_UNIFORM_INT);
}

/* --- picking */

XT3D_API int xt3d_GetRayCollisionModel(float ray_px, float ray_py, float ray_pz,
                                               float ray_dx, float ray_dy, float ray_dz, int model)
{
    Ray ray = {{ray_px, ray_py, ray_pz}, {ray_dx, ray_dy, ray_dz}};
    Model *m = xt_Model(model);
    RayCollision best; memset(&best, 0, sizeof(best));
    for (int i = 0; i < m->meshCount; i++) {
        RayCollision c = GetRayCollisionMesh(ray, m->meshes[i], m->transform);
        if (c.hit && (!best.hit || c.distance < best.distance)) best = c;
    }
    return xt_set("%d,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g", (int)best.hit, (double)best.distance,
        (double)best.point.x, (double)best.point.y, (double)best.point.z,
        (double)best.normal.x, (double)best.normal.y, (double)best.normal.z);
}

/* --- frames for LiveCode
 * A LiveCode image's imageData is 4 bytes per pixel: one unused byte, then red,
 * green, blue, rows from the top. Its alphaData is one byte per pixel.
 * Render textures come back from the GPU as RGBA with the bottom row first. */

static unsigned char *xt_frame = NULL;
static unsigned char *xt_alpha = NULL;
static int xt_frame_bytes = 0;

static Image xt_grab(int target)
{
    Image img = LoadImageFromTexture(xt_RenderTexture(target)->texture);
    if (img.data && img.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8)
        ImageFormat(&img, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
    return img;
}

XT3D_API bool xt3d_RenderTextureExport(int target, const char *fileName)
{
    if (!IsWindowReady()) return false;   /* no window yet: no GPU to talk to */
    Image img = xt_grab(target);
    if (!img.data) return false;
    ImageFlipVertical(&img);
    bool ok = ExportImage(img, fileName);
    UnloadImage(img);
    return ok;
}

XT3D_API void *xt3d_RenderTextureToImageData(int target)
{
    if (!IsWindowReady()) { xt_frame_bytes = 0; return xt_frame; }   /* no window yet: no frame */
    Image img = xt_grab(target);
    if (!img.data) { xt_frame_bytes = 0; return xt_frame; }
    int w = img.width, h = img.height, bytes = w * h * 4;
    if (bytes != xt_frame_bytes) {
        xt_frame = (unsigned char *)realloc(xt_frame, (size_t)bytes);
        xt_alpha = (unsigned char *)realloc(xt_alpha, (size_t)(w * h));
        xt_frame_bytes = bytes;
    }
    const unsigned char *src = (const unsigned char *)img.data;
    for (int y = 0; y < h; y++) {
        const unsigned char *s = src + (size_t)(h - 1 - y) * (size_t)w * 4;
        unsigned char *d = xt_frame + (size_t)y * (size_t)w * 4;
        unsigned char *al = xt_alpha + (size_t)y * (size_t)w;
        for (int x = 0; x < w; x++) {
            d[0] = 0; d[1] = s[0]; d[2] = s[1]; d[3] = s[2];
            al[x] = s[3];
            d += 4; s += 4;
        }
    }
    UnloadImage(img);
    return xt_frame;
}

XT3D_API int xt3d_ImageDataSize(void) { return xt_frame_bytes; }
XT3D_API int xt3d_AlphaDataSize(void) { return xt_frame_bytes / 4; }

/* Alpha of the frame most recently converted by xt3d_RenderTextureToImageData;
 * converts first when asked for a different target. */
XT3D_API void *xt3d_RenderTextureToAlphaData(int target)
{
    if (!xt_alpha) xt3d_RenderTextureToImageData(target);
    return xt_alpha;
}

/* --- meshes from numbers
 * Builds and uploads a mesh from text lists, so geometry can be made in script.
 *   vertices   x,y,z per vertex
 *   texcoords  u,v per vertex, or empty
 *   indices    three vertex numbers (0-based) per triangle, or empty for
 *              "every three vertices are a triangle"
 * Numbers may be separated by commas, spaces or line breaks. Normals are
 * computed (smooth when indexed, flat otherwise). Indexed meshes are limited
 * to 65535 vertices. Returns a mesh handle, or 0 on bad input. */

static int xt_parse_floats(const char *text, float **out)
{
    int n = 0, cap = 256;
    float *v = (float *)malloc(sizeof(float) * (size_t)cap);
    const char *p = text ? text : "";
    while (*p) {
        char *end;
        double d = strtod(p, &end);
        if (end == p) { p++; continue; }
        if (n == cap) { cap *= 2; v = (float *)realloc(v, sizeof(float) * (size_t)cap); }
        v[n++] = (float)d;
        p = end;
    }
    *out = v;
    return n;
}

XT3D_API int xt3d_MeshFromText(const char *vertices, const char *texcoords, const char *indices)
{
    if (!IsWindowReady()) return 0;   /* no window yet: no GPU to talk to */
    float *vf = NULL, *tf = NULL, *xf = NULL;
    int nv = xt_parse_floats(vertices, &vf) / 3;
    int nt = xt_parse_floats(texcoords, &tf) / 2;
    int ni = xt_parse_floats(indices, &xf);
    int ok = nv >= 3 && (nt == 0 || nt == nv) && (ni % 3 == 0) && (ni > 0 ? nv <= 65535 : nv % 3 == 0);
    for (int i = 0; ok && i < ni; i++) if (xf[i] < 0 || (int)xf[i] >= nv) ok = 0;
    if (!ok) { free(vf); free(tf); free(xf); return 0; }

    Mesh mesh; memset(&mesh, 0, sizeof(mesh));
    mesh.vertexCount = nv;
    mesh.triangleCount = ni > 0 ? ni / 3 : nv / 3;
    mesh.vertices = (float *)MemAlloc((unsigned int)(sizeof(float) * 3 * (size_t)nv));
    mesh.normals  = (float *)MemAlloc((unsigned int)(sizeof(float) * 3 * (size_t)nv));
    memcpy(mesh.vertices, vf, sizeof(float) * 3 * (size_t)nv);
    memset(mesh.normals, 0, sizeof(float) * 3 * (size_t)nv);
    if (nt) {
        mesh.texcoords = (float *)MemAlloc((unsigned int)(sizeof(float) * 2 * (size_t)nv));
        memcpy(mesh.texcoords, tf, sizeof(float) * 2 * (size_t)nv);
    }
    if (ni) {
        mesh.indices = (unsigned short *)MemAlloc((unsigned int)(sizeof(unsigned short) * (size_t)ni));
        for (int i = 0; i < ni; i++) mesh.indices[i] = (unsigned short)xf[i];
    }
    for (int t = 0; t < mesh.triangleCount; t++) {
        int a = ni ? mesh.indices[t * 3] : t * 3, b = ni ? mesh.indices[t * 3 + 1] : t * 3 + 1, c = ni ? mesh.indices[t * 3 + 2] : t * 3 + 2;
        const float *pa = vf + a * 3, *pb = vf + b * 3, *pc = vf + c * 3;
        float ux = pb[0] - pa[0], uy = pb[1] - pa[1], uz = pb[2] - pa[2];
        float wx = pc[0] - pa[0], wy = pc[1] - pa[1], wz = pc[2] - pa[2];
        float nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
        int idx[3] = {a, b, c};
        for (int k = 0; k < 3; k++) {
            mesh.normals[idx[k] * 3] += nx; mesh.normals[idx[k] * 3 + 1] += ny; mesh.normals[idx[k] * 3 + 2] += nz;
        }
    }
    for (int i = 0; i < nv; i++) {
        float *n = mesh.normals + i * 3;
        double len2 = (double)n[0] * n[0] + (double)n[1] * n[1] + (double)n[2] * n[2];
        if (len2 > 0) {
            double inv = 1.0, g = len2;
            /* Newton square root keeps this file free of libm */
            double r = g > 1 ? g : 1; for (int it = 0; it < 40; it++) r = 0.5 * (r + g / r);
            inv = 1.0 / r;
            n[0] = (float)(n[0] * inv); n[1] = (float)(n[1] * inv); n[2] = (float)(n[2] * inv);
        } else { n[1] = 1.0f; }
    }
    free(vf); free(tf); free(xf);
    UploadMesh(&mesh, false);
    return xt_new_Mesh(mesh);
}

XT3D_API int xt3d_MeshInfo(int mesh)
{
    Mesh *m = xt_Mesh(mesh);
    return xt_set("%d,%d,%d", m->vertexCount, m->triangleCount, m->indices ? 1 : 0);
}

/* --- render state (rlgl)
 * Each change first flushes what has been drawn so far, so it applies only to
 * what is drawn afterwards. Set these between Begin... and End... calls. */

XT3D_API void xt3d_SetBackfaceCulling(bool enabled)
{
    if (!IsWindowReady()) return;   /* no window yet: there is no GPU state to change */
    rlDrawRenderBatchActive();
    if (enabled) rlEnableBackfaceCulling(); else rlDisableBackfaceCulling();
}

/* 0 = cull front faces (shows inside-out models correctly), 1 = cull back faces (normal) */
XT3D_API void xt3d_SetCullFace(int mode)
{
    if (!IsWindowReady()) return;   /* no window yet: there is no GPU state to change */
    rlDrawRenderBatchActive();
    rlSetCullFace(mode);
}

XT3D_API void xt3d_SetWireMode(bool enabled)
{
    if (!IsWindowReady()) return;   /* no window yet: there is no GPU state to change */
    rlDrawRenderBatchActive();
    if (enabled) rlEnableWireMode(); else rlDisableWireMode();
}

XT3D_API void xt3d_SetDepthTest(bool enabled)
{
    if (!IsWindowReady()) return;   /* no window yet: there is no GPU state to change */
    rlDrawRenderBatchActive();
    if (enabled) rlEnableDepthTest(); else rlDisableDepthTest();
}

XT3D_API void xt3d_SetLineWidth(float width)
{
    if (!IsWindowReady()) return;   /* no window yet: there is no GPU state to change */
    rlDrawRenderBatchActive();
    rlSetLineWidth(width);
}

/* --- diagnostics */

/* --- raylib log to a file
 * raylib reports what it loads and why something failed through TraceLog, which
 * normally goes to a console LiveCode never shows. This sends it to a text file,
 * flushed line by line so the log survives a crash. Empty name: back to the console. */

static FILE *xt_log = NULL;

static void xt_log_line(int level, const char *text, va_list args)
{
    static const char *names[] = {"ALL", "TRACE", "DEBUG", "INFO", "WARNING", "ERROR", "FATAL", "NONE"};
    if (!xt_log) return;
    fprintf(xt_log, "%s: ", (level >= 0 && level <= 7) ? names[level] : "?");
    vfprintf(xt_log, text, args);
    fputc('\n', xt_log);
    fflush(xt_log);
}

XT3D_API bool xt3d_SetTraceLogFile(const char *fileName)
{
    if (xt_log) { fclose(xt_log); xt_log = NULL; }
    if (!fileName || !fileName[0]) { SetTraceLogCallback(NULL); return true; }
    xt_log = fopen(fileName, "w");
    SetTraceLogCallback(xt_log ? xt_log_line : NULL);
    return xt_log != NULL;
}

XT3D_API int xt3d_HandleCount(const char *typeName)
{
    if (!typeName) return 0;
#define XT_CNT(T) if (strcmp(typeName, #T) == 0) return xt_count_##T();
    XT_CNT(Image) XT_CNT(Texture) XT_CNT(RenderTexture) XT_CNT(Font) XT_CNT(Mesh) XT_CNT(Shader)
    XT_CNT(Material) XT_CNT(Model) XT_CNT(ModelAnimation) XT_CNT(Wave) XT_CNT(Sound) XT_CNT(Music)
    XT_CNT(AudioStream) XT_CNT(Camera3D) XT_CNT(Camera2D)
#undef XT_CNT
    return -1;
}
