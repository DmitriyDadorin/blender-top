"""Prepare licensed recordings and two original noise beds for the game mixer."""
from pathlib import Path
import argparse, array, math, subprocess, tempfile, wave
ROOT=Path(__file__).resolve().parents[1]/'audio'
SOURCE=ROOT/'source'

def pcm(path,filters=''):
    command=['ffmpeg','-v','error','-i',str(path)]
    if filters:command+=['-af',filters]
    command+=['-f','f32le','-ac','2','-ar','44100','-']
    data=array.array('f');data.frombytes(subprocess.check_output(command));return data

def save(name,data,loop=True,blend=.10):
    if loop:
        n=min(int(44100*blend),len(data)//8)
        middle=array.array('f',data[n*2:-n*2])
        for frame in range(n):
            t=frame/max(1,n-1)
            for channel in range(2):middle.append(data[len(data)-n*2+frame*2+channel]*(1-t)+data[frame*2+channel]*t)
        data=middle
    else:
        n=int(44100*.015)
        for frame in range(min(n,len(data)//2)):
            gain=frame/n
            for channel in range(2):
                data[frame*2+channel]*=gain
                data[-frame*2-channel-1]*=gain
    rms=math.sqrt(sum(x*x for x in data)/max(1,len(data)))
    peak=max(abs(x) for x in data)
    gain=min(.14/max(rms,.000001),.85/max(peak,.000001))
    encoded=array.array('h',(round(max(-1,min(1,x*gain))*32767) for x in data))
    with tempfile.NamedTemporaryFile(suffix='.wav') as f:
        with wave.open(f.name,'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(44100);w.writeframes(encoded.tobytes())
        (ROOT/(name+'.wav')).write_bytes(Path(f.name).read_bytes())
    print(name,round(len(data)/88200,2),'s','peak',round(peak*gain,3))

def prepare_rolling():
    # Distant, low road texture rather than bright broadband hiss. Filtering
    # twice gives a gentle but steep enough roll-off before runtime playback.
    for name,color,filters in [
        ('road_roll','pink','highpass=f=55,lowpass=f=700,lowpass=f=700'),
        ('wind','brown','highpass=f=35,lowpass=f=500,lowpass=f=500'),
    ]:
        with tempfile.NamedTemporaryFile(suffix='.wav') as f:
            subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i',f'anoisesrc=color={color}:duration=6:sample_rate=44100:seed=1729','-af',filters,f.name],check=True)
            save(name,pcm(f.name),blend=.25)

parser=argparse.ArgumentParser(description=__doc__)
selection=parser.add_mutually_exclusive_group()
selection.add_argument('--engine-only',action='store_true',help='Rebuild only the replacement V8 recordings')
selection.add_argument('--rolling-only',action='store_true',help='Rebuild only road and wind textures')
args=parser.parse_args()
if args.rolling_only:
    prepare_rolling()
    raise SystemExit(0)

# Real 1964 Chrysler exhaust recording, with the same steady eight-second take
# for both layers. Matching loop lengths and playback rates avoid two unrelated
# engine notes beating against each other. Keep the natural exhaust pulses.
engine=SOURCE/'chrysler_v8_exhaust.mp3'
take='atrim=start=12:end=20,asetpts=PTS-STARTPTS,highpass=f=32'
save('engine_idle',pcm(engine,take+',bass=g=2:f=110,lowpass=f=800'),blend=.12)
save('engine_load',pcm(engine,take+',bass=g=2:f=130,equalizer=f=1200:t=q:w=0.8:g=-3,lowpass=f=2100'),blend=.12)
save('engine_start',pcm(engine,'atrim=start=0.65:end=2.8,asetpts=PTS-STARTPTS,highpass=f=32,lowpass=f=2400'),False)
if args.engine_only:raise SystemExit(0)
save('horn',pcm(SOURCE/'Car_Horn.ogg'),False)
save('handbrake',pcm(SOURCE/'Car_Parking_Brake.ogg'),False)
save('tyre_skid',pcm(SOURCE/'tyre_skid.wav','highpass=f=200,lowpass=f=6200'),blend=.16)
save('city_traffic',pcm(SOURCE/'city_traffic.ogg','highpass=f=90,lowpass=f=6500'),blend=.4)
save('ocean_waves',pcm(SOURCE/'ocean_waves.flac','highpass=f=70,lowpass=f=6500'),blend=.5)
prepare_rolling()
