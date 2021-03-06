function Sequence =  trkTracking(folder, resultsFolder, SeqIndexStr, Sample, magnification)
%% define the folder locations and filenames of the images
Gfolder = [folder 'green/'];
Rfolder = [folder 'red/'];
Gfiles = dir([Gfolder '*.TIF']);
Rfiles = dir([Rfolder '*.TIF']);

if ~exist('TMAX', 'var'); TMAX =  length(Rfiles); end; % number of time steps
if TMAX~=length(Gfiles)
   disp(['problem with data in directory: ' folder]);
   return;
end

%% Load the raw data
IntensityAjustmentGreen.MED = 2537;
IntensityAjustmentGreen.STD = 28.9134;
IntensityAjustmentGreen.MAX = 11234;
IntensityAjustmentRed.MED = 205;
IntensityAjustmentRed.STD = 3.0508;
IntensityAjustmentRed.MAX = 327;

[Red  , Red_Original]   = trkReadImagesAndNormalize(TMAX, Rfolder, IntensityAjustmentRed);
[Green, Green_Original] = trkReadImagesAndNormalize(TMAX, Gfolder, IntensityAjustmentGreen);

%% Detect Nuclei
disp('...detecting Nuclei');
% paramaters
% Smoothing the sigma for the red channel
SIGMA_RED         = 2.0;
if strcmp(magnification, '10x')
    MAX_NUCLEUS_AREA  = 170; %  > pi*7*7
    MIN_NUCLEUS_AREA  =  70; %  < pi*5*5
elseif strcmp(magnification, '20x')
    MAX_NUCLEUS_AREA  = 750; %  > pi*15*15
    MIN_NUCLEUS_AREA  = 300; %  < pi*10*10
end
% MaxVariation and Delta are default values from www.vlfeat.org/api/mser_8h.html
MSER_MaxVariation = 0.2;
MSER_Delta        = 2;

tic
Nuclei = trkDetectNuclei(Red, SIGMA_RED, MIN_NUCLEUS_AREA, MAX_NUCLEUS_AREA, MSER_MaxVariation, MSER_Delta);
toc


%% detect the Somata using region growing
disp('...detecting somata');

GEODESIC_DISTANCE_THRESH = 2e-6;
if strcmp(magnification, '10x')
    LENGTH_THRESH = 7;
elseif strcmp(magnification, '20x')
    LENGTH_THRESH = 12;
end
STD_MULT_FACTOR = 1.5;

tic
Somata = trkDetectSomataGlobal(Nuclei, Green, GEODESIC_DISTANCE_THRESH, LENGTH_THRESH, STD_MULT_FACTOR);
toc

%% Gather detections into cells
disp('...gather detections into cells');

CellsFilteringParameters.DISTANCE_TO_BOUNDARY = 10;
CellsFilteringParameters.MAX_ECCENTRICITY     = 0.85;
CellsFilteringParameters.MIN_CIRCULARITY      = 0.2;

tic
[Cells CellsList] = trkGatherNucleiAndSomataDetections(Green_Original, Red_Original, Nuclei, Somata, CellsFilteringParameters);
toc


%% Generate graph and track
disp('...tracking');
% parameters
if strcmp(magnification, '10x')
    SPATIAL_WINDOWS_SIZE = 50;
elseif strcmp(magnification, '20x')
    SPATIAL_WINDOWS_SIZE = 100;
end

GreedyTrackingParameters.TEMPORAL_WINDOWS_SIZE = 4; % do not touch
GreedyTrackingParameters.SPATIAL_WINDOWS_SIZE  = SPATIAL_WINDOWS_SIZE; % do not touch
GreedyTrackingParameters.MIN_TRACK_LENGTH      = 20; % si durr??e de vie < 20, pas pris en compte
GreedyTrackingParameters.NB_BEST_TRACKS        = 40; % on prend les 40 meilleurs tracks en fonction de l'intensit??
GreedyTrackingParameters.WT                    = 50; % do not touch
GreedyTrackingParameters.WSH                   = 40; % do not touch
GreedyTrackingParameters.W_THRESH              = 200; % do not touch

tic
[Cells, tracks, trkSeq, timeSeq] = trkTrackCellsGreedy(CellsList, Cells, GreedyTrackingParameters);%#ok
toc;

%% preprocessing Frangi
disp('...detecting neurites and ssign them to cells');

% frangi parameters
if strcmp(magnification, '10x')
    FrangiOpt.FrangiScaleRange = [1 2];
    
    NeuriteDetectionParams.minimalSizeOfNeurite = 10;
elseif strcmp(magnification, '20x')
    FrangiOpt.FrangiScaleRange = [1 3];
    
    NeuriteDetectionParams.minimalSizeOfNeurite = 20;
else
    error(['Resolution should be wither 10x or 20x but it is ' magnification]);
end
FrangiOpt.FrangiScaleRatio = 1; % do not touch
FrangiOpt.FrangiBetaOne = .5; % do not touch
FrangiOpt.FrangiBetaTwo = 15; % do not touch
FrangiOpt.BlackWhite = false;
FrangiOpt.verbose = false;

NeuriteDetectionParams.GEODESIC_DISTANCE_NEURITE_THRESH = 0.0001; % do not touch
NeuriteDetectionParams.KeyPointDetectionParam           = 5; % do not touch
%%%%%%%%%%% This is the neurites detection parameter %%%%%%%%%%
%%%%%%%%%%% It should take values between 0 and 1 strictly.
NeuriteDetectionParams.NeuriteProbabilityThreshold      = 0.2;
%%%%%%%%%%% This is the neurites detection parameter %%%%%%%%%%
NeuriteDetectionParams.NeuritePruningLengthThreshold    = 10;

tic
[Cells] = trkDetectAndAddFilamentsToCells(Green_Original, Cells, Somata, FrangiOpt, IntensityAjustmentGreen, NeuriteDetectionParams);    
toc

%% track neurites
disp('...tracking neurites');
if strcmp(magnification, '10x')
    NEURITE_STABILITY_LENGTH_THRESHOLD = 30; % do not touch
elseif strcmp(magnification, '20x')
    NEURITE_STABILITY_LENGTH_THRESHOLD = 60; % do not touch
end

NeuriteTrackingParams.NEURITE_STABILITY_LENGTH_THRESHOLD = NEURITE_STABILITY_LENGTH_THRESHOLD;
NeuriteTrackingParams.W_THRESH                           = 800;
NeuriteTrackingParams.MIN_TRACK_LENGTH                   = 10; % do not touch

tic
[TrackedNeurites, TrackedNeuritesList, trkNSeq, timeNSeq] = trkTrackNeurites(Cells, CellsList, timeSeq, NeuriteTrackingParams);
toc

%% render results on the video
disp('...make movie');
% parameters
cols = color_list();

tic
mv = trkRenderImagesAndTracks(Green, Cells, CellsList, tracks, SeqIndexStr, Sample, cols );
% make a movie of the results
movfile = SeqIndexStr ;
trkMovie(mv, resultsFolder, resultsFolder, movfile); fprintf('\n');
toc

Cells = rmfield(Cells, 'Neurites');

%% reorganize data
disp('...reorganizing data ')
tic
Sequence = trkReorganizeDataStructure(folder, Rfiles, Gfiles, Green_Original, Red_Original, Sample, SeqIndexStr, Cells, trkSeq, TrackedNeurites, TrackedNeuritesList, trkNSeq, timeNSeq);
toc
%%
save([resultsFolder SeqIndexStr],  'Sequence');