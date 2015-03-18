
FileName = 'test2.DSG';
if numel(FileName) <= 5
SAMPTIME_LEN = 0; % 2 * 2
WRITETIME_LEN = 0; % 4 * 2
else
SAMPTIME_LEN = 4; % 2 * 2
WRITETIME_LEN = 8; % 4 * 2
end
fid=fopen(FileName);
if(fid<1)
    disp('Unable to Open File');
    return
end 

% Read in DF_Head
DF_HEAD.Version = fread(fid,1,'uint32');
DF_HEAD.UserID = fread(fid,1,'uint32');
DF_HEAD.sec = fread(fid,1,'uint8');
DF_HEAD.min = fread(fid,1,'uint8');
DF_HEAD.hour = fread(fid,1,'uint8');
DF_HEAD.day = fread(fid,1,'uint8');
DF_HEAD.mday = fread(fid,1,'uint8');
DF_HEAD.month = fread(fid,1,'uint8');
DF_HEAD.year = fread(fid,1,'uint8'); 
DF_HEAD.timezone = fread(fid,1,'int8');

%DF_HEAD.NU = fread(fid,16,'uint32');

if(DF_HEAD.Version>=1010) 
    DF_HEAD.Lat=fread(fid,1,'float32');
    DF_HEAD.Lon=fread(fid,1,'float32');
    DF_HEAD.depth=fread(fid,1,'float32');
    DF_HEAD.DSGcal=fread(fid,1,'float32');
    DF_HEAD.hydroCal=fread(fid,1,'float32');
    DF_HEAD.lpFilt=fread(fid,1,'float32');
end
    
pos = ftell(fid); 
% Read in SID_SPECS until get all zeroes
notdone=1;
SID_SPEC=[];
nSIDSPEC=1;
while(notdone)
    SID_SPEC(nSIDSPEC).SID = fread(fid,4,'uint8=>char');
    SID_SPEC(nSIDSPEC).nBytes = fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).NumChan = fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).StoreType = fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).SensorType = fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).DForm = fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).SPus = fread(fid,1,'uint32'); % Sample period (us) x 256
    SID_SPEC(nSIDSPEC).RECPTS=fread(fid,1,'uint32');
    SID_SPEC(nSIDSPEC).RECINT=fread(fid,1,'uint32');
    
    if(SID_SPEC(nSIDSPEC).nBytes==0)
        notdone=0;
    end
    nSIDSPEC=nSIDSPEC+1; 
end
nSIDSPEC=nSIDSPEC-1;
SID_SPEC(nSIDSPEC)=[];  % delete last one with all zeroes
nSIDSPEC=nSIDSPEC-1;



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%               Below are my modifications
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
HEAD_LEN = ftell(fid); % the length of header bytes above
% SAMPTIME_LEN = 4; % 2 * 2
% WRITETIME_LEN = 8; % 4 * 2
% listing = dir(FileName);
fseek(fid, 0, 'eof');
fileLen = ftell(fid);
fseek(fid, HEAD_LEN, 'bof');
SENSOR_SPEC_LEN = 10;
BUFFER_LEN = SID_SPEC(1).nBytes;
SAMP_LEN = SID_SPEC(1).NumChan * 2 + SAMPTIME_LEN; % 2bytesPerChan + sampleTime

nBuffer = ceil((fileLen - HEAD_LEN)/(BUFFER_LEN+SENSOR_SPEC_LEN));
nSampPerBuff = (BUFFER_LEN - WRITETIME_LEN)/SAMP_LEN;
nSamp = nBuffer * nSampPerBuff;
if nSIDSPEC > 1
    sampleRatio = SID_SPEC(2).SPus/SID_SPEC(1).SPus;
%     if WRITETIME_LEN == 0
%         nRecLen = nSensorData + ceil(nSensorData/sampleRatio);
%     else
        nSamp = nSamp + ceil(nSamp/sampleRatio);
        nBuffer = nBuffer + ceil(nSamp/sampleRatio);
%     end   
end


% Read in next SID_REC header and data
eofstat=0;
iBuffer=0;
iSample = 1;
pos = ftell(fid);

clear SID_REC
SID_REC(nBuffer, 1) = struct;
writeTime = nan(nBuffer, 2);
sampleTime = nan(nSamp, 2);
% accel = nan(nSamp, 3);
% mag = nan(nSamp, 3);
% gyro = nan(nSamp, 3);


% sample = SAMPLE_LEN
%%
thisSensorId = 1;
if(bitand(SID_SPEC(thisSensorId).SensorType,32))
    accelLen = 3;
    nAccelSampPerBuff = nSampPerBuff;
    accelSeek = -SAMP_LEN*nAccelSampPerBuff+6;
else
    accelLen = 0;
    nAccelSampPerBuff = 0;
    accelSeek = 0;
end

if(bitand(SID_SPEC(thisSensorId).SensorType,16))
    magLen = 3;
    nMagSampPerBuff = nSampPerBuff;
    magSeek = -SAMP_LEN*nMagSampPerBuff+6;
else
    magLen = 0;
    nMagSampPerBuff = 0;
    magSeek = 0;
end

if(bitand(SID_SPEC(thisSensorId).SensorType,8))
    gyroLen = 3;
    nGyroSampPerBuff = nSampPerBuff;
    gyroSeek = -SAMP_LEN*nGyroSampPerBuff+6;
else
    gyroLen = 0;
    nGyroSampPerBuff = 0;
    gyroSeek = 0;
end
SAMPTIME_SKIP = SAMP_LEN - SAMPTIME_LEN/2;
INER_LEN = (accelLen + magLen + gyroLen);
INER_SKIP = (accelLen + magLen + gyroLen)*2 - 6 + SAMPTIME_LEN;
sampBegSeek = -SAMP_LEN*nSampPerBuff+SAMPTIME_SKIP;
sampEndSeek = -SAMP_LEN*nSampPerBuff-SAMPTIME_SKIP + SAMPTIME_LEN/2;


iner = nan(nSamp, INER_LEN);
inerPrec = sprintf('%d*int16', INER_LEN);
%%
while(eofstat==0)
% for i = 1:4600
    if pos == 372604
        a = 1;
    end
    iBuffer = iBuffer + 1;
    thisSensorId = fread(fid,1,'uint8') + 1;
    fseek(fid, 9, 'cof');
    if WRITETIME_LEN ~= 0
        writeTime(iBuffer, :) = fread(fid, 2, 'uint32');
    end
    if(thisSensorId <= numel(SID_SPEC))         
        if(SID_SPEC(thisSensorId).DForm==2)
            nsamples=(SID_SPEC(thisSensorId).nBytes)/2;  %/2 because in bytes
                pos = ftell(fid); 
                if SAMPTIME_LEN ~= 0
                    thisSampleBeg = fread(fid, nSampPerBuff, 'uint16', SAMPTIME_SKIP);
                    fseek(fid, sampBegSeek, 'cof');
                    thisSampleEnd = fread(fid, nSampPerBuff, 'uint16', SAMPTIME_SKIP);
                    fseek(fid, sampEndSeek, 'cof');
                    sampleTime(iSample:iSample+nSampPerBuff-1, :) = ...
                        [thisSampleBeg thisSampleEnd];
                end 
                
%                 accel(iSample:iSample+nAccelSampPerBuff-1, 1:accelLen) = ...
%                     fread(fid, [accelLen, nAccelSampPerBuff], '3*int16', INER_SKIP)';
%                 fseek(fid, accelSeek, 'cof');
% 
%                 mag(iSample:iSample+nMagSampPerBuff-1, 1:magLen) = ...
%                     fread(fid, [magLen, nMagSampPerBuff], '3*int16', INER_SKIP)';
%                 fseek(fid, magSeek, 'cof');
% 
%                 gyro(iSample:iSample+nGyroSampPerBuff-1, 1:gyroLen) = ...
%                     fread(fid, [gyroLen, nGyroSampPerBuff], '3*int16', INER_SKIP)';
%                 fseek(fid, gyroSeek, 'cof');
                
                iner(iSample:iSample + nSampPerBuff - 1, :) = ...
                    fread(fid, [INER_LEN, nSampPerBuff], inerPrec, SAMPTIME_LEN)';
                iSample = iSample + nSampPerBuff;
                fseek(fid, pos + SAMP_LEN*nSampPerBuff, 'bof');
        end
        if(SID_SPEC(thisSensorId).DForm==3)
            nsamples=SID_SPEC(thisSensorId).nBytes;
            SID_REC(iBuffer).data=fread(fid,nsamples,'uint8');  % 24-bit samples read in 8 bits at a time
        end
    end
     
    pos = ftell(fid);
    if pos >= fileLen;
        eofstat = 1;
    end
end

%%
% figure; 
% subplot(311)
% plot(accel*16/4096)
% subplot(312)
% plot(mag*1/1090)
% subplot(313)
% plot(gyro*500/32768)
