function [estimate, ParticleFilterDS, pNoise, oNoise, extra] = gmsppf(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)

% GMSPPF  Gaussian Mixture Sigma-Point Particle Filter
%
%   [estimate, ParticleFilterDS, pNoise, oNoise] = gmsppf(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)
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
%   Required InferenceDS fields:
%         .spkfType            (string) Type of SPKF to use (srukf or srcdkf).
%         .estimateType        (string) Estimate type : 'mean', 'mode', etc.
%
%   NOTE : All covariances are assumed to be of type 'sqrt', i.e. Cholesky factors.
%
%   See also
%   PF, SPPF, GSPF
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

if (nargin ~= 7) error(' [ gmsppf ] Not enough input arguments.'); end

switch pNoise.ns_type
case 'gmm'
otherwise
  error(' [ gmsppf ] Process noise source must be of type : gmm (Gaussian Mixture Model)');
end

switch oNoise.ns_type
case 'gmm'
otherwise
  error(' [ gmsppf ] Observation noise source must be of type : gmm (Gaussian Mixture Model)');
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
R    = oNoise.M;        % number of components in observation noise GMM

GK  = G*K;
GKR = GK*R;

stateWPrior   = zeros(1,GK);
stateMuPrior  = zeros(Xdim,GK);
stateCovPrior = zeros(Xdim,Xdim,GK);
stateWNew     = zeros(1,GKR);
stateMuNew    = zeros(Xdim,GKR);
stateCovNew   = zeros(Xdim,Xdim,GKR);

stateMu  = stateGMM.mu;
stateCov = stateGMM.cov;
stateW   = stateGMM.weights;

pNoiseW  = pNoise.weights;
oNoiseW  = oNoise.weights;

cov_type = stateGMM.cov_type;

switch cov_type
case {'full','diag'}
  error(' [ gspf ] Currently the GSPF algorithm only support state GMMs which has ''sqrt'' covariance types.');
end


ones_numP = ones(numP,1);
ones_Xdim = ones(1,Xdim);
ones_GK   = ones(GK,1);
ones_GKR  = ones(GKR,1);

NOV = size(obs,2);                                       % number of input vectors

if (U1dim==0), UU1=zeros(0,numP); Utemp1=[]; end
if (U2dim==0), UU2=zeros(0,numP); Utemp2=[]; end

estimate   = zeros(Xdim,NOV);

normfactO = (2*pi)^(Odim/2);

pNoiseSPKF = struct('mu',zeros(Vdim,1),'cov',zeros(Vdim),'adaptMethod',[]);
oNoiseSPKF = struct('mu',zeros(Ndim,1),'cov',zeros(Ndim),'adaptMethod',[]);

if (nargout > 4)
  extra.mu  = zeros(Xdim,G,NOV);
  extra.cov = zeros(Xdim,Xdim,G,NOV);
  extra.weights = zeros(1,G,NOV);
end


%================================================================================================
%--- MAIN LOOP over all data vectors

for i=1:NOV,

    OBStemp = obs(:,i);                % inline cvecrep
    OBS = OBStemp(:,ones_numP);

    if U1dim
      Utemp1 = U1(:,i);
      UU1 = Utemp1(:,ones_numP);        % inline cvecrep
    end
    if U2dim
      Utemp2 = U2(:,i);
      UU2 = Utemp2(:,ones_numP);        % inline cvecrep
    end


    %-----------------------------------------------------------------------
    % TIME UPDATE

    for r=1:R,
        oNoiseSPKF.mu = oNoise.mu(:,r);
        oNoiseSPKF.cov = oNoise.cov(:,:,r);
        for k=1:K,
            pNoiseSPKF.mu  = pNoise.mu(:,k);
            pNoiseSPKF.cov = pNoise.cov(:,:,k);
            for g=1:G,

                a = g + (k-1)*G;
                j = a + (r-1)*(GK);

                switch InferenceDS.spkfType
                case 'srukf'
                  [stateMuNew(:,j),stateCovNew(:,:,j),pNoiseSPKF,oNoiseSPKF,intvarDS] = ...
                    srukf(stateMu(:,g), stateCov(:,:,g), pNoiseSPKF, oNoiseSPKF, OBStemp, Utemp1, Utemp2, InferenceDS);
                case 'srcdkf'
                  [stateMuNew(:,j),stateCovNew(:,:,j),pNoiseSPKF,oNoiseSPKF,intvarDS] = ...
                    srcdkf(stateMu(:,g), stateCov(:,:,g), pNoiseSPKF, oNoiseSPKF, OBStemp, Utemp1, Utemp2, InferenceDS);
                otherwise
                    error(' [ gmsppf ] Unknown SPKF type.');
                end

                stateMuPrior(:,a)    = intvarDS.xh_;
                stateCovPrior(:,:,a) = intvarDS.Sx_;
                inov = intvarDS.inov;
                S    = intvarDS.Sinov;
                stateWPrior(1,a) = stateW(1,g)*pNoiseW(1,k);

                foo1 = S \ inov;
                foo2 = exp(-0.5*foo1'*foo1) / abs(normfactO*prod(diag(S))) + 1e-99;

                stateWNew(1,j)   = stateWPrior(1,a)*oNoiseW(1,r) * foo2;

            end
        end
    end

    stateWPrior = stateWPrior / sum(stateWPrior);
    stateWNew   = stateWNew / sum(stateWNew);


    %-----------------------------------------------------------------------
    % MEASUREMENT UPDATE

    % build temporary state GMM's
    priorStateGMM = struct('cov_type',cov_type,'mu',stateMuPrior,'cov',stateCovPrior,'weights',stateWPrior,'dim',Xdim,'M',GK);
    newStateGMM = struct('cov_type',cov_type,'mu',stateMuNew,'cov',stateCovNew,'weights',stateWNew,'dim',Xdim,'M',GKR);

    % Draw samples from the Gaussian Mixture proposal
    XsampleBuf = gmmsample(newStateGMM,numP);

    % evaluate likelihood of each particle under the transition prior (have to average over distribution of X_k-1)
    [p1,p2,prior] = gmmprobability(priorStateGMM, XsampleBuf);

    % calculate observation likelihood for each particle
    likelihood = InferenceDS.likelihood( InferenceDS, OBS, XsampleBuf, UU2, oNoise) + 1e-99;

    % evaluate likelihood of each particle under the proposal density
    [p1,p2,proposal] = gmmprobability(newStateGMM, XsampleBuf);

    % calculate importance weights
    sampleW = (likelihood.*prior)./proposal;
    sampleW = sampleW./sum(sampleW);


    %-----------------------------------------------------------------------
    % CALCULATE ESTIMATE


    %switch InferenceDS.estimateType
    %case 'mean'
    %    estimate(:,i) = XsampleBuf*sampleW';
    %case 'GMMmean'
    %    estimate(:,i) = stateMuNew*stateWNew';
    %otherwise
    %    error(' [ gmsppf ] Unknown estimate type.');
    %end

    estimate(:,i) = XsampleBuf*sampleW';

    %-----------------------------------------------------------------------
    % RESAMPLE

    outIndex  = residualresample(1:numP,sampleW);
    XsampleBuf = XsampleBuf(:,outIndex); % + eps*randn(Xdim,numP);
    sampleW = repmat(1/numP,1,numP);

    %-----------------------------------------------------------------------
    % Recover GMM representation of posterior distribution using EM

    ParticleFilterDS.particles = XsampleBuf;
    ParticleFilterDS.weights = sampleW;

    stateGMM = gmmfit(XsampleBuf, stateGMM, [0.001 10], cov_type, 1, 0);

    stateMu  = stateGMM.mu;
    stateCov = stateGMM.cov;
    stateW   = stateGMM.weights;

    if pNoise.adaptMethod
        error('  [ gmsppf ] Process noise adaptation not supported yet for GMM noise sources.');
    end

    if (nargout > 4)
      extra.mu(:,:,i) = stateMu;
      extra.cov(:,:,:,i) = stateCov;
      extra.weights(:,:,i) = stateW;
      extra.P = zeros(Xdim,Xdim);
      est = estimate(:,i);
      for kk=1:G,
        cS  = stateCov(:,:,kk);
        ttt = est-stateMu(:,kk);
        extra.P = extra.P + stateW(kk)*(cS*cS' + ttt*ttt');
      end
    end


%--------------------------------------------------------------------------
end     %.. loop over input vectors


ParticleFilterDS.stateGMM = stateGMM;

