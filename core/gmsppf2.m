function [estimate, ParticleFilterDS, pNoise, oNoise] = gmsppf2(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)

% GMSPPF2 : SPBF  Sigma-Point Bayes Filter
%
%   [estimate, ParticleFilterDS, pNoise, oNoise] = SPBF2(ParticleFilterDS, pNoise, oNoise, obs, U1, U2, InferenceDS)
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

error(' GMSPPF2 : Sigma-Point Bayes Filter not implemented yet! ');
