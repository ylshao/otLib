% addpath('e:\')
%%
% FileName = '1416.DSG';
FileName = 'test3.DSG';
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

% accel = nan(nSamp, 3);
% mag = nan(nSamp, 3);
% gyro = nan(nSamp, 3);

sampleTime = nan(nSamp, 2);
% sample = SAMPLE_LEN
%%
thisSensorId = 1;
if(bitand(SID_SPEC(thisSensorId).SensorType,32))
    accelLen = 3;
else
    accelLen = 0;
end

if(bitand(SID_SPEC(thisSensorId).SensorType,16))
    magLen = 3;
else
    magLen = 0;
end

if(bitand(SID_SPEC(thisSensorId).SensorType,8))
    gyroLen = 3;
else
    gyroLen = 0;
end
SAMPTIME_SKIP = SAMP_LEN - SAMPTIME_LEN/2;
INER_LEN = (accelLen + magLen + gyroLen);
INER_SKIP = (accelLen + magLen + gyroLen)*2 - 6 + SAMPTIME_LEN;

if SAMPTIME_LEN ~= 0
    nTimeSampPerBuff = nSampPerBuff;
    sampBegSeek = -SAMP_LEN*nSampPerBuff+SAMPTIME_SKIP;
    sampEndSeek = -SAMP_LEN*nSampPerBuff-SAMPTIME_SKIP + SAMPTIME_LEN/2;
    SAMPARRAY_LEN = 2;
else
    nTimeSampPerBuff = 0;
    sampBegSeek = 0;
    sampEndSeek = 0;
    SAMPARRAY_LEN = 0;
end
if WRITETIME_LEN ~= 0
    nWriteTime = 2;
else
    nWriteTime = 0;
end
iner = nan(nSamp, INER_LEN);
inerPrec = sprintf('%d*int16', INER_LEN);
%%
while(eofstat==0)
% for i = 1:4600
    if pos == 372604
        a = 1;
    end
    iBuffer = iBuffer + 1;
    head = fread(fid,10,'uint8');
    thisSensorId = head(1)+1;
%     fseek(fid, 9, 'cof');
    writeTime(iBuffer, 1:nWriteTime) = fread(fid, nWriteTime, 'uint32');        
    if thisSensorId ~= 1
        a = 1;
    end
    if(SID_SPEC(thisSensorId).DForm==2)
        nsamples=(SID_SPEC(thisSensorId).nBytes)/2;  %/2 because in bytes
            iner(iSample:iSample + nSampPerBuff - 1, :) = ...
                fread(fid, [INER_LEN, nSampPerBuff], inerPrec, SAMPTIME_LEN)';    
% Order of the iner and sample, change the fseek, or only use one fseek
            fseek(fid, -SAMPTIME_LEN-(nSampPerBuff-1)*SAMP_LEN, 'cof');
            sampleTime(iSample:iSample+nTimeSampPerBuff-1, :) = ...
                fread(fid, [2, nSampPerBuff], '2*uint16', 18)';
            fseek(fid, -18, 'cof');
             
            iSample = iSample + nSampPerBuff;
    end 
% Avoid the IF condition for telling whether it is pressure of iner
    if(SID_SPEC(thisSensorId).DForm==3)
        nsamples=SID_SPEC(thisSensorId).nBytes;
        SID_REC(iBuffer).data=fread(fid,nsamples,'uint8');  % 24-bit samples read in 8 bits at a time
    end

% Better way to end the iteration, avoid the two steps
    pos = ftell(fid);
    if pos >= fileLen - BUFFER_LEN; % 
        eofstat = 1;
    end
end

%%
% accel = iner(:, 1:3);
% mag = iner(:, 4:6);
% gyro = iner(:, 7:9);
% figure; 
% subplot(311)
% plot(accel*16/4096)
% subplot(312)
% plot(mag*1/1090)
% subplot(313)
% plot(gyro*500/32768)
