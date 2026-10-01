import numpy as np, cv2, sys
P=120.0
def L(f): return cv2.cvtColor(cv2.imread(f),cv2.COLOR_BGR2GRAY).astype(np.float64)
def geom(Wpt,Hpt): hpt,wpt=64,300; cy=Hpt/2+0.2*(Hpt/2-hpt/2); return Wpt/2-wpt/2, cy-hpt/2, wpt, hpt
bins=[(0.3,1),(1,2),(2,3),(3,4),(4,6),(6,8),(8,10),(10,13),(13,16),(16,20),(20,25),(25,31)]
def measure(D,Wpt,Hpt,variant,side,k=3):
    x0,y0,w,h=geom(Wpt,Hpt); out={}
    for wall,page,axis in [('end','hramp',1),('top','vramp',0)]:
        R=L(f'{D}/{page}-{variant}-none.png'); G=L(f'{D}/{page}-{variant}-{side}.png')
        H,W=R.shape; yy,xx=np.mgrid[:H,:W].astype(np.float64)+0.5
        X=xx/k; Y=yy/k
        r=h/2; cx1=x0+r; cx2=x0+w-r; cy=y0+h/2
        px=np.clip(X,cx1,cx2); dx=X-px; dy=Y-cy; dist=np.hypot(dx,dy); inward=r-dist
        pos=X if axis==1 else Y
        # reference ramp model check: value ~ frac(pos/P)*255
        # calibrate glass tone: affine fit on interior pixels (inward>25) mid-tooth
        if wall=='end':
            frac_ref=R/255.0
            inner=(inward>25)&(frac_ref>0.15)&(frac_ref<0.85)
            a,b=np.polyfit(R[inner],G[inner],1)
            tone=(a,b)
        else:
            a,b=tone
        src_frac=np.clip((G-b)/a/255.0,0,1)
        base=np.floor(pos/P)*P
        cands=np.stack([base-P+src_frac*P, base+src_frac*P, base+P+src_frac*P])
        src=cands[np.argmin(np.abs(cands-pos[None]),axis=0),np.arange(H)[:,None],np.arange(W)[None,:]]
        # displacement along outward normal: + means content from farther out
        if wall=='end': n=-1.0; sel=(X<cx1)&(np.abs(dy)<r*0.3)
        else: n=-1.0; sel=(np.abs(X-(cx1+cx2)/2)<w*0.25)&(dy<0)
        disp=(src-pos)*n
        gfrac=(G-b)/a/255.0
        ok=sel&(gfrac>0.08)&(gfrac<0.92)
        prof=[]
        for d0,d1 in bins:
            m=ok&(inward>=d0)&(inward<d1)
            prof.append(np.median(disp[m]) if m.sum()>15 else np.nan)
        # interior magnification: slope of src vs pos in inward 20-30 region along axis
        m=ok&(inward>12)
        if wall=='end': m=(np.abs(dy)<r*0.3)&(X>cx1+5)&(X<cx1+60)&(gfrac>0.2)&(gfrac<0.8)
        else: m=(np.abs(X-(cx1+cx2)/2)<w*0.25)&(inward>20)&(gfrac>0.2)&(gfrac<0.8)
        out[wall]=(prof,a,b)
    return out
D,W,H=sys.argv[1],float(sys.argv[2]),float(sys.argv[3])
print('bins(pt)            '+' '.join(f'{f"{a}-{b}":>6s}' for a,b in bins))
for variant in ['clear','regular']:
    for side in ['apple','ours']:
        o=measure(D,W,H,variant,side)
        for wall in ['top','end']:
            prof,a,b=o[wall]
            print(f'{variant:7s} {side:5s} {wall:3s}  '+' '.join(f'{v:6.2f}' for v in prof)+f'   tone a={a:.2f} b={b:.0f}')
