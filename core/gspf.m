function [estimate, ParticleFilterDS, pNoise, oNoise] = gspf(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)

% GSPF  Gaussian Sum Particle Filter
%
%   This is an implementation of Jayesh H. Kotecha and Petar M. Djuric's
%   'Gaussian Sum Particle Filter' as presented in:
%
%   Jayesh H. Kotecha and Petar M. Djuric, "Gaussian Sum Particle
%   Filtering for Dynamic State Space Models", Proceedings of ICASSP-2001,
%   Salt Lake City, Utah, May 2001.
%
%   [estimate, ParticleFilterDS, pNoise, oNoise] = GSPF(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)
%
%   This filter assumes the following standard state-space model:
%
%     x(k) = ffun[x(k-1),v(k-1),U1(k-1)]
%     y(k) = hfun[x(k),n(k),U2(k)]
%
%   where x is the system state, v the process noise, n the observation noise, u1 the exogenous input to the state
%   transition function, u2 the exogenous input to the state observation function and y the noisy observation of the
%   system.
%
%   INPUT
%         ParticleFilterDS     Particle filter data structure. (see field definitions below)
%         pNoise               (NoiseDS) process noise data structure  (must be of type 'gmm')
%         oNoise               (NoiseDS) observation noise data structure
%         obs                  noisy observations starting at time k ( y(k),y(k+1),...,y(k+N-1) )
%         U1                   exogenous input to state transition function starting at time k-1 ( u1(k-1),u1(k),...,u1(k+N-2) )
%         U2                   exogenous input to state observation function starting at time k  ( u2(k),u2(k+1),...,u2(k+N-1) )
%         InferenceDS          Inference data structure generated by GENINFDS function.
%
%   OUTPUT
%         estimate             State estimate generated from posterior distribution of state given all observation. Type of
%                              estimate is specified by InferenceDS.estimateType
%         ParticleFilterDS     Updated Particle filter data structure.
%         pNoise               process noise data structure     (possibly updated)
%         oNoise               observation noise data structure (possibly updated)
%
%   ParticleFilterDS fields:
%         .N                   (scalar) number of particles to use
%         .stateGMM            (gmm) Gaussian mixture model of state distribution with the following field:
%                  .M            (scalar) number of mixture components in GMM
%                  .mu           (statedim-by-M) buffer of mean vectors (centroids) of state GMM components
%                  .cov          (statedim-by-statedim-my-M) buffer of covariance matrices of state GMM components
%                  .cov_type     (string) covariance matrix type ('full','sqrt','diag','swrt-diag') 'sqrt' is preferred.
%                  .weights      (1-by-M) state GMM component weights (priors)
%
%
%   Required InferenceDS fields:
%         .estimateType        (string) Estimate type : 'mean', 'mode', etc.
%
%   NOTE : All covariances are assumed to be of type 'sqrt', i.e. Cholesky factors.
%
%   See also
%   PF, SPPF
%   Copyright (c) Oregon Health & Science University (2006)
%
%   This file is part of the ReBEL Toolkit. The ReBEL Toolkit is available free for
%   academic use only (see included license file) and can be obtained from
%   http://choosh.csee.ogi.edu/rebel/.  Businesses wishing to obtain a copy of the
%   software should contact rebel@csee.ogi.edu for commercial licensing information.
%
%   See LICENSE (which should be part of the main toolkit distribution) for more
%   detail.

%=============================================================================================

if (nargin ~= 7) error(' [ gspf ] Not enough input arguments.'); end

switch pNoise.ns_type
case 'gmm'
otherwise
  error(' [ gspf ] Process noise source must be of type : gmm (Gaussian Mixture Model)');
end


Xdim  = InferenceDS.statedim;                            % extract state dimension
Odim  = InferenceDS.obsdim;                              % extract observation dimension
U1dim = InferenceDS.U1dim;                               % extract exogenous input 1 dimension
U2dim = InferenceDS.U2dim;                               % extract exogenous input 2 dimension
Vdim  = InferenceDS.Vdim;                                % extract process noise dimension
Ndim  = InferenceDS.Ndim;                                % extract observation noise dimension

numP = ParticleFilterDS.N;            % number of particles to use for SIR

stateGMM = ParticleFilterDS.stateGMM;

G    = stateGMM.M;      % number of components in state GMM
K    = pNoise.M;        % number of components in process noise GMM

GK  = G*K;

sampleBuf1 = zeros(Xdim,numP,G);     % sample buffer : (sample dimension) X (number of samples) X (number of mixcomps)
sampleBuf2 = zeros(Xdim,numP,GK);
stateWNew = zeros(1,GK);

sampleBuf3 = zeros(Xdim,numP,GK);
impWeights = zeros(GK,numP);

stateMu  = stateGMM.mu;
stateCov = stateGMM.cov;
stateW   = stateGMM.weights;

cov_type = stateGMM.cov_type;

switch cov_type
case {'full','diag'}
  error(' [ gspf ] Currently the GSPF algorithm only support state GMMs which has ''sqrt'' covariance types.');
end


stateMuNew  = zeros(Xdim,GK);
stateCovNew = zeros(Xdim,Xdim,GK);

pNoiseW = pNoise.weights;

ones_numP = ones(numP,1);
ones_Xdim = ones(1,Xdim);
ones_GK   = ones(GK,1);

NOV = size(obs,2);                                       % number of input vectors

if (U1dim==0), UU1=zeros(0,numP); end
if (U2dim==0), UU2=zeros(0,numP); end

estimate   = zeros(Xdim,NOV);


%================================================================================================
%--- MAIN LOOP over all data vectors

for i=1:NOV,

    OBStemp = obs(:,i);                % inline cvecrep
    OBS = OBStemp(:,ones_numP);

    if U1dim
      Utemp = U1(:,i);
      UU1 = Utemp(:,ones_numP);        % inline cvecrep
    end
    if U2dim
      Utemp = U2(:,i);
      UU2 = Utemp(:,ones_numP);        % inline cvecrep
    end


    %-----------------------------------------------------------------------
    % TIME UPDATE

    for g=1:G,                                 % draw M samples from each state GMM component
        temp_mu = stateMu(:,g);
        % It is assumed that the covariances are Cholesky factors
        sampleBuf1(:,:,g) = stateCov(:,:,g) * randn(Xdim,numP) + temp_mu(:,ones_numP);
    end

    for k=1:K,
        cS  = pNoise.cov(:,:,k);       % get process noise GMM component covariance
        cMu = pNoise.mu(:,k);
        cMuBuf = cMu(:,ones_numP);
        for g=1:G,
            gk = g + (k-1)*G;
            pNoiseBuf = cS * randn(Vdim,numP) + cMuBuf;
            sampleBuf2(:,:,gk) = InferenceDS.ffun( InferenceDS, sampleBuf1(:,:,g), pNoiseBuf, UU1);
            stateWNew(1,gk) = stateW(1,g) * pNoiseW(1,k);
        end
    end

    stateWNew = stateWNew / sum(stateWNew);

    for gk=1:GK,                                    % inline sample mean and covariance
        muFoo = sum(sampleBuf2(:,:,gk),2)/numP;
        stateMuNew(:,gk) = muFoo;
        muFoo = muFoo(:,ones_numP);
        Xfoo = sampleBuf2(:,:,gk) - muFoo;
        [foo,covFoo] = qr(Xfoo',0);
        stateCovNew(:,:,gk) = covFoo'/sqrt(numP-1);
    end


    %-----------------------------------------------------------------------
    % MEASUREMENT UPDATE


    % Calculate observed samples and importance weights
    for gk=1:GK,
        temp_mu = stateMuNew(:,gk);
        sampleBuf3(:,:,gk) = stateCovNew(:,:,gk) * randn(Xdim,numP) + temp_mu(:,ones_numP);
        impWeights(gk,:) = InferenceDS.likelihood( InferenceDS, OBS, sampleBuf3(:,:,gk), UU2, oNoise) + 1e-99;
    end

    weightNorm = 0;

    % Calculate updated state mixcomp means, covariances and weights
    for gk=1:GK,

        weightFoo = impWeights(gk,:);
        impWeightM = weightFoo(ones_Xdim,:);   % inline rvecrep
        impWeightNorm = sum(weightFoo);
        muFoo2 = sum(impWeightM.*sampleBuf3(:,:,gk),2) / impWeightNorm;
        stateMuNew(:,gk) = muFoo2;

        xdel = sampleBuf3(:,:,gk) - muFoo2(:,ones_numP); % inline cvecrep
        weightSFoo = sqrt(weightFoo);
        impWeightSM = weightSFoo(ones_Xdim,:);

        Xfoo = impWeightSM.*xdel;

        [foo,covFoo] = qr(Xfoo',0);
        stateCovNew(:,:,gk) = covFoo'/sqrt(impWeightNorm);

        stateWNew(:,gk) = stateWNew(:,gk)*impWeightNorm;   % part 1 of equation (11)
        weightNorm = weightNorm + impWeightNorm;

    end

    % Calculate updated and normalized mixcomp weights
    stateWNew = stateWNew / weightNorm;                   % part 2 of equation (11)
    stateWNew = stateWNew / sum(stateWNew);               % normalize


    %-----------------------------------------------------------------------
    % CALCULATE ESTIMATE

    switch InferenceDS.estimateType

    case 'mean'
        muFoo = sum(stateWNew(ones_Xdim,:).*stateMuNew,2);
        estimate(:,i) = muFoo;

    otherwise
        error(' [ sppf ] Unknown estimate type.');

    end


    %-----------------------------------------------------------------------
    % RESAMPLE MIXTURE COMPONENTS

    resampleIdx = residualresample(1:GK,stateWNew);
    [fooIdx,rIdx]=sort(rand(1,GK));                  % inline randperm
    rIdx=rIdx(1:G);

    idx = resampleIdx(rIdx);
    stateMu = stateMuNew(:,idx);
    stateCov = stateCovNew(:,:,idx);

    stateW = (1/G) * ones(1,G);

    if pNoise.adaptMethod
        error('  [ gspf ] Process noise adaptation not supported yet for GMM noise sources.');
    end


%--------------------------------------------------------------------------
end     %.. loop over input vectors


ParticleFilterDS.stateGMM.cov      = stateCov;
ParticleFilterDS.stateGMM.mu       = stateMu;
ParticleFilterDS.stateGMM.weights  = stateW;

