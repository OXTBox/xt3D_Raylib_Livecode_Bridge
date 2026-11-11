#!/usr/bin/env python3
"""gen_xt3d.py - generate the xt3d bridge from raylib.h

  python3 gen_xt3d.py raylib.h

Writes: xt3d_generated.inc (C wrappers, included by xt3d_shim.c),
        xt3d.lcb (LiveCode Builder library), xt3d_raylib_manifest.json

Flattening rules
  scalars and strings ............ passed through
  Vector2/3/4, Rectangle, Matrix,
  Ray, BoundingBox ............... spread into floats
  Color .......................... 4 integers 0-255
  Image, Texture, Model, Sound ... integer handle (0 = invalid)
  struct return values ........... comma-separated string, e.g. "1.5,0,2"
Functions that need raw pointers, arrays, callbacks or varargs are skipped
and listed in the manifest with the reason.
"""
import re, sys, json, itertools

VALUE = {  # by-value math structs: (C field expressions, code per field, printf fmt)
 'Vector2':   (['x','y'],'f'), 'Vector3': (['x','y','z'],'f'),
 'Vector4':   (['x','y','z','w'],'f'), 'Quaternion': (['x','y','z','w'],'f'),
 'Rectangle': (['x','y','width','height'],'f'),
 'Color':     (['r','g','b','a'],'i'),
 'Matrix':    (['m%d'%i for i in range(16)],'f'),
 'Ray':       (['position.x','position.y','position.z','direction.x','direction.y','direction.z'],'f'),
 'BoundingBox':(['min.x','min.y','min.z','max.x','max.y','max.z'],'f'),
}
RES = {'Image':'Image','Texture':'Texture','Texture2D':'Texture','TextureCubemap':'Texture',
 'RenderTexture':'RenderTexture','RenderTexture2D':'RenderTexture','Font':'Font','Mesh':'Mesh',
 'Shader':'Shader','Material':'Material','Model':'Model','ModelAnimation':'ModelAnimation',
 'Wave':'Wave','Sound':'Sound','Music':'Music','AudioStream':'AudioStream',
 'Camera3D':'Camera3D','Camera':'Camera3D','Camera2D':'Camera2D'}
RES_TYPES = sorted(set(RES.values()))
SCALAR = {'int':'i','unsigned int':'u','float':'f','double':'d','bool':'b','long':'l'}
CTYPE  = {'i':'int','u':'unsigned int','f':'float','d':'double','b':'bool','l':'long','s':'const char *','p':'void *','h':'int'}
LCBT   = {'i':'CInt','u':'CUInt','f':'CFloat','d':'CDouble','b':'CBool','l':'CLong','s':'ZStringNative','p':'Pointer','h':'CInt'}
LCBPUB = {'i':'Number','u':'Number','f':'Number','d':'Number','l':'Number','h':'Number','b':'Boolean','s':'String','p':'Pointer'}
SIG    = {'i':'i','u':'i','l':'i','h':'i','f':'f','d':'f','b':'b','s':'s','p':'p'}
SKIP_NAMES = {'SetWindowIcons':'takes an array of images'}  # pointer-to-resource parameters that are really arrays

def sigcode(codes):
    out=''
    for k,g in itertools.groupby(SIG[c] for c in codes):
        n=len(list(g)); out += (str(n) if n>1 else '')+k
    return out

def parse(header):
    funcs=[]; module='core'
    for line in header.splitlines():
        m=re.match(r'//\s*(.*?)\s*\(Module: (\w+)\)',line)
        if m: module=m.group(2)
        m=re.match(r'RLAPI\s+(.*?)(\w+)\((.*)\);\s*(?://\s*(.*))?$',line)
        if not m: continue
        ret,name,params,doc=m.group(1).strip(),m.group(2),m.group(3).strip(),(m.group(4) or '').strip()
        plist=[]
        if params!='void':
            for p in params.split(','):
                p=p.strip()
                if p=='...': plist.append(('...','')); continue
                pm=re.match(r'(.*?)(\w+)$',p)
                plist.append((re.sub(r'\s+',' ',pm.group(1)).strip(),pm.group(2)))
        funcs.append(dict(name=name,ret=re.sub(r'\s+',' ',ret),params=plist,doc=doc,module=module))
    return funcs

def flatten(f):
    """returns (cparams[(name,code)], call_args[str], after[str], retcode, retexpr builder) or raises"""
    if f['name'] in SKIP_NAMES: raise ValueError(SKIP_NAMES[f['name']])
    if f['name'] in HELPER_NAMES: raise ValueError('replaced by the xt3d helper of the same name')
    if f['name'].startswith('Text') and f['module']=='text': raise ValueError('string utility; use LiveCode text handling')
    cp=[]; args=[]; after=[]
    for t,n in f['params']:
        if t=='...': raise ValueError('variable arguments')
        base=t.replace('const ','').strip()
        if base in SCALAR: cp.append((n,SCALAR[base])); args.append(n)
        elif base=='char *' and t.startswith('const'): cp.append((n,'s')); args.append(n)
        elif base in VALUE:
            fields,code=VALUE[base]; names=[n+'_'+x.replace('.','_') for x in fields]
            cp += [(x,code) for x in names]
            if base=='Color': args.append('(Color){'+','.join('(unsigned char)'+x for x in names)+'}')
            elif base=='Matrix': args.append('xt_matrix('+','.join(names)+')')
            elif base in('Ray','BoundingBox'): args.append('('+base+'){{%s,%s,%s},{%s,%s,%s}}'%tuple(names))
            else: args.append('('+base+'){'+','.join(names)+'}')
        elif base=='NPatchInfo':
            names=[n+'_'+x for x in ('x','y','width','height','left','top','right','bottom','layout')]
            cp += [(x,'f') for x in names[:4]]+[(x,'i') for x in names[4:]]
            args.append('(NPatchInfo){{%s,%s,%s,%s},%s,%s,%s,%s,%s}'%tuple(names))
        elif base in RES: cp.append((n,'h')); args.append('*xt_%s(%s)'%(RES[base],n))
        elif base.endswith(' *') and base[:-2] in RES and not t.startswith('const'):
            cp.append((n,'h')); args.append('xt_%s(%s)'%(RES[base[:-2]],n))
        elif 'Callback' in base: raise ValueError('callback parameter')
        else: raise ValueError('parameter type '+t)
    r=f['ret']; rb=r.replace('const ','').strip()
    call='%s(%s)'%(f['name'],', '.join(args))
    if f['name'].startswith('Unload') and f['params'] and f['params'][0][0] in RES:
        after.append('xt_free_%s(%s);'%(RES[f['params'][0][0]],f['params'][0][1]))
    if f['name']=='InitWindow': call='if (!IsWindowReady()) '+call  # a second InitWindow would orphan every GPU resource
    if r=='void': rc='v'; body=call+';'
    elif rb in SCALAR: rc=SCALAR[rb]; body='return '+call+';'
    elif rb=='char *' and r.startswith('const'): rc='s'; body='return xt_set("%s", xt_str('+call+'));'
    elif r=='void *' and f['name']=='GetWindowHandle': rc='p'; body='return '+call+';'
    elif rb in VALUE:
        fields,code=VALUE[rb]; rc='s'
        fmt=','.join(['%d' if code=='i' else '%.9g']*len(fields))
        cast='(int)' if code=='i' else '(double)'
        body='%s r = %s; return xt_set("%s", %s);'%(rb,call,fmt,', '.join(cast+'r.'+x for x in fields))
    elif rb=='RayCollision':
        rc='s'; body=('RayCollision r = %s; return xt_set("%%d,%%.9g,%%.9g,%%.9g,%%.9g,%%.9g,%%.9g,%%.9g", (int)r.hit, (double)r.distance, '
          '(double)r.point.x,(double)r.point.y,(double)r.point.z,(double)r.normal.x,(double)r.normal.y,(double)r.normal.z);')%call
    elif rb in RES: rc='h'; body='return xt_new_%s(%s);'%(RES[rb],call)
    else: raise ValueError('return type '+r)
    if after:
        if rc!='v': raise ValueError('unload with return')
        body=body+' '+' '.join(after)
    return cp,rc,body

# hand-written helpers in xt3d_shim.c: (name, return code, [(param,code)], description)
def P(s): return [(n,c) for n,c in (x.split(':') for x in s.split())] if s else []
CAM3='px:f py:f pz:f tx:f ty:f tz:f ux:f uy:f uz:f fovy:f projection:i'
EXTRA=[
 ('Version','s','', 'Bridge and raylib version string'),
 ('InitHidden','v','width:i height:i title:s','Open the raylib window hidden, for rendering into a LiveCode image'),
 ('CameraCreate','h',CAM3,'Create a 3D camera; returns a camera handle'),
 ('CameraSet','v','camera:h '+CAM3,'Replace every field of a 3D camera'),
 ('CameraGet','s','camera:h','Camera fields as px,py,pz,tx,ty,tz,ux,uy,uz,fovy,projection'),
 ('CameraFree','v','camera:h','Release a 3D camera handle'),
 ('Camera2DCreate','h','offsetX:f offsetY:f targetX:f targetY:f rotation:f zoom:f','Create a 2D camera; returns a handle'),
 ('Camera2DSet','v','camera:h offsetX:f offsetY:f targetX:f targetY:f rotation:f zoom:f','Replace every field of a 2D camera'),
 ('Camera2DFree','v','camera:h','Release a 2D camera handle'),
 ('ImageInfo','s','image:h','width,height,mipmaps,format of an image'),
 ('TextureInfo','s','texture:h','id,width,height,mipmaps,format of a texture'),
 ('RenderTextureGetTexture','h','target:h','Borrowed texture handle for a render texture colour buffer; do not unload'),
 ('ModelInfo','s','model:h','meshCount,materialCount,boneCount of a model'),
 ('ModelGetMesh','h','model:h index:i','Borrowed mesh handle from a model (0-based); do not unload'),
 ('ModelSetTransform','v','model:h '+' '.join('m%d:f'%i for i in range(16)),'Set the local transform matrix of a model'),
 ('ModelGetTransform','s','model:h','Local transform matrix of a model as 16 numbers m0..m15'),
 ('ModelSetMaterialTexture','v','model:h material:i mapType:i texture:h','Set a texture on one of a model\'s materials'),
 ('ModelSetMaterialColor','v','model:h material:i mapType:i r:i g:i b:i a:i','Set a map colour on one of a model\'s materials'),
 ('ModelSetMaterialShader','v','model:h material:i shader:h','Set the shader of one of a model\'s materials'),
 ('MaterialSetColor','v','material:h mapType:i r:i g:i b:i a:i','Set a map colour on a standalone material'),
 ('MaterialSetShader','v','material:h shader:h','Set the shader of a standalone material'),
 ('LoadModelAnimations','s','fileName:s','Load every animation in a file; returns firstHandle,count (handles are consecutive)'),
 ('UnloadModelAnimations','v','firstHandle:h','Unload an animation set returned by LoadModelAnimations'),
 ('ModelAnimationInfo','s','anim:h','name,boneCount,keyframeCount of an animation'),
 ('SetShaderValueFloats','v','shader:h locIndex:i count:i a:f b:f c:f d:f','Set a float, vec2, vec3 or vec4 uniform (count = 1..4)'),
 ('SetShaderValueInt','v','shader:h locIndex:i value:i','Set an int or sampler uniform'),
 ('GetRayCollisionModel','s','ray_px:f ray_py:f ray_pz:f ray_dx:f ray_dy:f ray_dz:f model:h','Nearest ray hit over every mesh of a model: hit,distance,px,py,pz,nx,ny,nz'),
 ('RenderTextureExport','b','target:h fileName:s','Save a render texture to an image file, right way up'),
 ('RenderTextureToImageData','p','target:h','Pointer to the frame converted to LiveCode imageData layout (0RGB, top row first)'),
 ('ImageDataSize','i','','Byte count of the buffer last produced by RenderTextureToImageData'),
 ('AlphaDataSize','i','','Byte count of the alpha buffer (one byte per pixel)'),
 ('RenderTextureToAlphaData','p','target:h','Pointer to the frame alpha channel, one byte per pixel, top row first'),
 ('MeshFromText','h','vertices:s texcoords:s indices:s','Build and upload a mesh from number lists: x,y,z per vertex; optional u,v per vertex; optional 0-based triangle indices'),
 ('MeshInfo','s','mesh:h','vertexCount,triangleCount,indexed(0/1) of a mesh'),
 ('SetBackfaceCulling','v','enabled:b','Turn back-face culling on or off for what is drawn next'),
 ('SetCullFace','v','mode:i','Which faces to cull: 0 = front (for inside-out models), 1 = back (normal)'),
 ('SetWireMode','v','enabled:b','Draw what follows as wireframe'),
 ('SetDepthTest','v','enabled:b','Turn depth testing on or off for what is drawn next'),
 ('SetLineWidth','v','width:f','Line width for what is drawn next'),
 ('ResultLength','i','','Length in bytes of the most recent text result (diagnostic)'),
 ('ResultByte','i','index:i','One byte of the most recent text result, 0-based (diagnostic)'),
 ('HandleCount','i','typeName:s','Number of live handles of a type such as "Model" or "Texture"'),
]

HELPER_NAMES={e[0] for e in EXTRA}

def main():
    hdr=open(sys.argv[1] if len(sys.argv)>1 else 'raylib.h').read()
    ver=re.search(r'RAYLIB_VERSION\s+"([^"]+)"',hdr).group(1)
    funcs=parse(hdr); entries=[]; inc=[]
    for f in funcs:
        e=dict(raylib=f['name'],module=f['module'],description=f['doc'],
               c_prototype='%s %s(%s)'%(f['ret'],f['name'],', '.join((t+' '+n).strip() for t,n in f['params']) or 'void'))
        try:
            cp,rc,body=flatten(f)
        except ValueError as ex:
            e.update(status='skipped',reason=str(ex)); entries.append(e); continue
        cname='xt3d_'+f['name']
        inc.append('XT3D_API %s %s(%s) { %s }'%(('int' if rc=='s' else CTYPE.get(rc,'void')) if rc!='v' else 'void',cname,
                   ', '.join(CTYPE[c]+(' ' if not CTYPE[c].endswith('*') else '')+n for n,c in cp) or 'void',body))
        e.update(status='wrapped',xt3d=cname,signature=sigcode([c for _,c in cp]),returns=SIG.get(rc,''),
                 params=[dict(name=n,type=LCBPUB[c],handle=(c=='h')) for n,c in cp],
                 returns_type={'v':'nothing','h':'handle','s':'string','b':'boolean','p':'pointer'}.get(rc,'number'),
                 _lcb=(cp,rc))
        entries.append(e)
    for name,rc,ps,doc in EXTRA:
        cp=P(ps)
        entries.append(dict(raylib=None,module='xt3d',description=doc,status='helper',xt3d='xt3d_'+name,
            signature=sigcode([c for _,c in cp]),returns=SIG.get(rc,''),
            params=[dict(name=n,type=LCBPUB[c],handle=(c=='h')) for n,c in cp],
            returns_type={'v':'nothing','h':'handle','s':'string','b':'boolean','p':'pointer'}.get(rc,'number'),_lcb=(cp,rc)))
    open('xt3d_generated.inc','w').write('/* generated by gen_xt3d.py from raylib %s - do not edit */\n'%ver+'\n'.join(inc)+'\n')
    # ---- LCB
    L=['-- generated by gen_xt3d.py from raylib %s - do not edit'%ver,'library org.xtalk.xtbridge','',
       'metadata title is "xt3d"','metadata author is "xt3d project"','metadata version is "0.1.0"','',
       'use com.livecode.foreign','',
       '-- Text results: the C side writes into its own buffer and returns the length;',
       '-- this reads the bytes back one at a time. No C string ever crosses the boundary.',
       'private handler xtResult(in pLength as Number) returns String',
       '\tvariable tOut as String','\tvariable tIndex as Number','\tvariable tCode as Number',
       '\tput "" into tOut',
       '\tput 0 into tIndex',
       '\trepeat while tIndex < pLength',
       '\t\tunsafe','\t\t\tput _xt3d_ResultByte(tIndex) into tCode','\t\tend unsafe',
       '\t\tput the char with code tCode after tOut',
       '\t\tadd 1 to tIndex',
       '\tend repeat','\treturn tOut','end handler','']
    for e in entries:
        if '_lcb' not in e: continue
        cp,rc=e['_lcb']; nm=e['xt3d']; priv='_'+nm
        fp=', '.join('in p%d as %s'%(i,LCBT[c]) for i,(n,c) in enumerate(cp))
        fr='nothing' if rc=='v' else ('CInt' if rc=='s' else LCBT[rc])
        L.append('private foreign handler %s(%s) returns %s binds to "c:xt3d>%s!cdecl"'%(priv,fp,fr,nm))
        pp=', '.join('in p%s as %s'%(n[0].upper()+n[1:],LCBPUB[c]) for n,c in cp)
        pr='nothing' if rc=='v' else LCBPUB[rc]
        callargs=', '.join('p%s'%(n[0].upper()+n[1:]) for n,c in cp)
        L.append('public handler %s(%s) returns %s'%(nm,pp,pr))
        if rc=='s':
            L += ['\tvariable tLength as Number','\tunsafe','\t\tput %s(%s) into tLength'%(priv,callargs),'\tend unsafe','\treturn xtResult(tLength)']
        else:
            L.append('\tunsafe')
            L.append(('\t\t%s(%s)' if rc=='v' else '\t\treturn %s(%s)')%(priv,callargs))
            L.append('\tend unsafe')
        L.append('end handler'); L.append('')
    L += ['-- Frame transfer: copies the latest converted frame into a Data value for "set the imageData of image"',
          'private foreign handler MCDataCreateWithBytes(in pBytes as Pointer, in pCount as LCUIndex, out rData as Data) returns CBool binds to "<builtin>"','',
          'public handler xt3d_RenderTextureImageData(in pTarget as Number) returns Data',
          '\tvariable tPtr as Pointer','\tvariable tData as Data',
          '\tunsafe',
          '\t\tput _xt3d_RenderTextureToImageData(pTarget) into tPtr',
          '\t\tMCDataCreateWithBytes(tPtr, _xt3d_ImageDataSize(), tData)','\tend unsafe','\treturn tData','end handler','',
          'public handler xt3d_RenderTextureAlphaData(in pTarget as Number) returns Data',
          '\tvariable tPtr as Pointer','\tvariable tData as Data',
          '\tunsafe',
          '\t\tput _xt3d_RenderTextureToAlphaData(pTarget) into tPtr',
          '\t\tMCDataCreateWithBytes(tPtr, _xt3d_AlphaDataSize(), tData)','\tend unsafe','\treturn tData','end handler','','end library','']
    open('xt3d.lcb','w').write('\n'.join(L))
    for e in entries: e.pop('_lcb',None)
    enums={}
    for m in re.finditer(r'typedef enum \{(.*?)\}\s*(\w+);',hdr,re.S):
        vals={}; cur=-1
        for ln in m.group(1).splitlines():
            ln=ln.split('//')[0].strip().rstrip(',')
            if not ln: continue
            if '=' in ln: k,v=[x.strip() for x in ln.split('=')]; cur=int(v,0)
            else: k=ln; cur+=1
            vals[k]=cur
        enums[m.group(2)]=vals
    colors={m.group(1):[int(x) for x in m.group(2).split(',')] for m in re.finditer(r'#define (\w+)\s+CLITERAL\(Color\)\{\s*([\d, ]+)\}',hdr)}
    n=lambda s: sum(1 for e in entries if e['status']==s)
    json.dump(dict(raylib_version=ver,counts=dict(raylib_functions=len(funcs),wrapped=n('wrapped'),skipped=n('skipped'),helpers=n('helper')),
        conventions=dict(handles='Images, textures, models, sounds, cameras etc. are positive integers; 0 means invalid',
            colors='Four integers 0-255: r,g,b,a', vectors='Spread into separate numbers',
            struct_returns='Comma-separated string', signature='s=string i=integer f=number b=boolean p=pointer; digit = repeat count'),
        functions=entries,enums=enums,colors=colors),open('xt3d_raylib_manifest.json','w'),indent=1)
    print('raylib',ver,'functions',len(funcs),'wrapped',n('wrapped'),'skipped',n('skipped'),'helpers',n('helper'))
if __name__=='__main__': main()
