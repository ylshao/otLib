
FileName = '1416.DSG';
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
HEAD_LEN = 112; % the length of header bytes above
SAMPTIME_LEN = 4; % 2 * 2
WRITETIME_LEN = 8; % 4 * 2
listing = dir(FileName);
fileLen = listing.bytes;
SENSOR_SPEC_LEN = 10;
BUFFER_LEN = SID_SPEC(1).nBytes;
SAMPLE_LEN = SID_SPEC(1).NumChan * 2 + SAMPTIME_LEN; % 2bytesPerChan + sampleTime

nBuffer = ceil((fileLen - HEAD_LEN)/(BUFFER_LEN+SENSOR_SPEC_LEN));
nSampPerBuff = (BUFFER_LEN - WRITETIME_LEN)/SAMPLE_LEN;
nSample = nBuffer * nSampPerBuff;
if nSIDSPEC > 1
    sampleRatio = SID_SPEC(1,2).SPus/SID_SPEC(1,1).SPus;
%     if WRITETIME_LEN == 0
%         nRecLen = nSensorData + ceil(nSensorData/sampleRatio);
%     else
        nSample = nSample + ceil(nSample/sampleRatio);
        nBuffer = nBuffer + ceil(nSample/sampleRatio);
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
sampleTime = nan(nSample, 2);
accel = nan(nSample, 3);
mag = nan(nSample, 3);
gyro = nan(nSample, 3);

% sample = SAMPLE_LEN
%%
while(eofstat==0)
% for i = 1:4600
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
                    thisSampleBeg = fread(fid, nSampPerBuff, 'uint16', 20);
                    fseek(fid, -22*nSampPerBuff+20, 'cof');
                    thisSampleEnd = fread(fid, nSampPerBuff, 'uint16', 20);
                    fseek(fid, -22*nSampPerBuff-18, 'cof');
                    sampleTime(iSample:iSample+nSampPerBuff-1, :) = ...
                        [thisSampleBeg thisSampleEnd];
                end 
                if(bitand(SID_SPEC(thisSensorId).SensorType,32))
                    accel(iSample:iSample+nSampPerBuff-1, :) = ...
                        fread(fid, [3, nSampPerBuff], '3*int16', 16)';
                    fseek(fid, -22*nSampPerBuff+6, 'cof');
                end
                if(bitand(SID_SPEC(thisSensorId).SensorType,16))
                    mag(iSample:iSample+nSampPerBuff-1, :) = ...
                        fread(fid, [3, nSampPerBuff], '3*int16', 16)';
                    fseek(fid, -22*nSampPerBuff+6, 'cof');
                end
                if(bitand(SID_SPEC(thisSensorId).SensorType,8))
                    gyro(iSample:iSample+nSampPerBuff-1, :) = ...
                        fread(fid, [3, nSampPerBuff], '3*int16', 16)';
                    fseek(fid, -22*nSampPerBuff+6, 'cof');
                end
                iSample = iSample + nSampPerBuff;
                fseek(fid, pos + 22*nSampPerBuff, 'bof');
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



