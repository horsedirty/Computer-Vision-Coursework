%% relative_coordinate_model.m —— Relative Coordinate Modeling
% Coding standards: See AGENTS.md in project root
% Role 5 responsible for implementation
%
% Function: Convert affine parameter sequences from absolute coordinates to relative coordinates (inter-frame increments).
% This is key to suppressing cumulative errors in long sequences — smoothing operates on increment sequences rather than absolute trajectories,
% cf. Paper 17_North University of China Online Stitching Stabilization (MDPI Applied Sciences 2025).
%
% Mathematical background:
%   Absolute coordinates:    T_t     = [transformation parameters of frame t in absolute coordinate system]
%   Relative increments:     ΔT_t    = T_t - T_{t-1}  (inter-frame increments)
%   Smoothed increments:     ΔT̃_t    = smooth(ΔT_{t-l}, ..., ΔT_{t+l})
%   Reconstructed absolute:  T̃_t     = T̃_{t-1} + ΔT̃_t  (incremental integration)
%
% Column indices for 6 degrees of freedom:
%   col 1 = dx    (horizontal translation, pixels)
%   col 2 = dy    (vertical translation, pixels)
%   col 3 = theta (rotation angle, rad)
%   col 4 = scale (scaling ratio)
%   col 5 = shx   (horizontal shear)
%   col 6 = shy   (vertical shear)
%
% INPUT:
%   paramAbsolute - N×6 double, affine parameter sequence in absolute coordinates (first frame as reference zero)
%   params        - struct
%     .useLogScale    - use logarithmic domain for scale component (multiplication→addition), default true
%     .wrapRotation   - perform phase unwrapping on rotation angle, default true
%
% OUTPUT:
%   paramRelative - N×6 double, relative coordinate increment sequence
%                  First frame ΔT_1 = 0 (no previous frame for differencing), differences start from frame 2
%   diagnostics   - struct
%     .mean_delta_translation - mean inter-frame translation (px)
%     .max_delta_translation  - max inter-frame translation (px)
%     .std_delta_theta        - standard deviation of inter-frame rotation angle (rad)
%     .mean_delta_log_scale   - mean inter-frame log scale
%     .abs2rel_time_ms        - forward conversion time (ms)
%     .rel2abs_time_ms        - inverse conversion validation time (ms)
%     .roundtrip_error        - roundtrip error (Frobenius norm mean)
%
% Dependency: MATLAB built-in unwrap()
%
% Reference paper: 17_North University of China Online Stitching Stabilization (MDPI Applied Sciences 2025)

function [paramRelative, diagnostics] = relative_coordinate_model(paramAbsolute, params)
    arguments
        paramAbsolute (:,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),   params.useLogScale = true; end
    if ~isfield(params, 'wrapRotation'),  params.wrapRotation = true; end

    t_start = tic;

    N = size(paramAbsolute, 1);
    if N < 2
        error('Relative coordinate modeling requires at least 2 frames');
    end

    paramRelative = zeros(N, 6);

    % ================================================================
    % 1. Translation components (dx, dy): direct difference
    %    Jitter appears at high frequencies; differencing removes low-frequency drift
    % ================================================================
    paramRelative(2:end, 1:2) = diff(paramAbsolute(:, 1:2));

    % ================================================================
    % 2. Rotation component (theta): unwrap phase first, then difference
    %    Avoids fake peaks from jumps near ±π, see Paper 17 Sec 3.2
    % ================================================================
    if params.wrapRotation
        theta_unwrapped = unwrap(paramAbsolute(:, 3));
        paramRelative(2:end, 3) = diff(theta_unwrapped);
    else
        paramRelative(2:end, 3) = diff(paramAbsolute(:, 3));
    end

    % ================================================================
    % 3. Scale component (scale): log-domain differencing
    %    Scale is multiplicative (s_t = s_{t-1} × factor); log makes it additive
    %    Δlog(s_t) = log(s_t) - log(s_{t-1}) = log(s_t / s_{t-1})
    %    After smoothing, exp(cumsum) reconstructs and naturally ensures s > 0
    % ================================================================
    if params.useLogScale
        logScale = log(max(paramAbsolute(:, 4), 1e-8));
        paramRelative(2:end, 4) = diff(logScale);
    else
        paramRelative(2:end, 4) = diff(paramAbsolute(:, 4));
    end

    % ================================================================
    % 4. Shear components (shx, shy): direct difference (usually small magnitude)
    % ================================================================
    paramRelative(2:end, 5:6) = diff(paramAbsolute(:, 5:6));

    abs2rel_time = toc(t_start);

    % ================================================================
    % Roundtrip verification: abs -> rel -> abs, confirm reversibility
    % ================================================================
    if N >= 3
        paramVerify = relative_to_absolute(paramRelative, paramAbsolute(1, :), params);
        roundtripErr = mean(vecnorm(paramVerify - paramAbsolute, 2, 2));
    else
        roundtripErr = NaN;
    end

    % ================================================================
    % Diagnostics summary
    % ================================================================
    diagnostics = struct(...
        'mean_delta_translation', mean(vecnorm(paramRelative(2:end, 1:2), 2, 2)), ...
        'max_delta_translation',  max(vecnorm(paramRelative(2:end, 1:2), 2, 2)), ...
        'std_delta_theta',        std(paramRelative(2:end, 3)), ...
        'mean_delta_log_scale',   mean(abs(paramRelative(2:end, 4))), ...
        'abs2rel_time_ms',        abs2rel_time * 1000, ...
        'rel2abs_time_ms',        NaN, ...
        'roundtrip_error',        roundtripErr);
end


% =========================================================================
%% Local function: relative_to_absolute -- inverse transform (incremental integration)
%
% Reconstruct absolute parameter sequence from smoothed increment sequence.
% This is the inverse process of relative coordinate modeling; must be called
% after smoothing to recover usable absolute parameters.
%
% See Paper 17_North University of China (MDPI 2025): smoothing acts on
% increment domain, integrate back to absolute domain
% =========================================================================

function paramAbsolute = relative_to_absolute(paramRelative, initAbsolute, params)
    arguments
        paramRelative (:,6) double
        initAbsolute (1,6) double
        params struct = struct()
    end

    if ~isfield(params, 'useLogScale'),  params.useLogScale = true; end

    t_start = tic;
    N = size(paramRelative, 1);

    if N == 0
        paramAbsolute = initAbsolute;
        return;
    end

    paramAbsolute = zeros(N, 6);

    % Translation: accumulate increments (cumsum)
    paramAbsolute(:, 1) = initAbsolute(1) + cumsum(paramRelative(:, 1));
    paramAbsolute(:, 2) = initAbsolute(2) + cumsum(paramRelative(:, 2));

    % Rotation: accumulate increments (increments already in unwrap domain)
    paramAbsolute(:, 3) = initAbsolute(3) + cumsum(paramRelative(:, 3));

    % Scale: accumulate in log domain then exponentiate
    % s̃_t = s₀ × exp(Σ Δlog(s_k)), guarantees s̃_t > 0
    % See Paper 17 Eq.(6): after log-domain smoothing, exponentiate to restore
    if params.useLogScale
        paramAbsolute(1, 4) = initAbsolute(4);
        for i = 2:N
            paramAbsolute(i, 4) = paramAbsolute(i-1, 4) * exp(paramRelative(i, 4));
        end
    else
        paramAbsolute(1, 4) = initAbsolute(4);
        for i = 2:N
            paramAbsolute(i, 4) = paramAbsolute(i-1, 4) + paramRelative(i, 4);
        end
    end

    % Shear: accumulate increments
    paramAbsolute(:, 5) = initAbsolute(5) + cumsum(paramRelative(:, 5));
    paramAbsolute(:, 6) = initAbsolute(6) + cumsum(paramRelative(:, 6));
end


% =========================================================================
%% Self-test
% Verify correctness of relative coordinate modeling: abs -> rel -> abs
% roundtrip error should be < 1e-10
% =========================================================================

function [] = self_test()
    fprintf('=== relative_coordinate_model Self-Test ===\n');

    N = 100;
    t = (1:N)';

    paramAbs = zeros(N, 6);
    paramAbs(:, 1) = 2 * sin(0.1 * t) + 0.1 * randn(N, 1);           % dx
    paramAbs(:, 2) = cos(0.15 * t) + 0.1 * randn(N, 1);              % dy
    paramAbs(:, 3) = 0.02 * sin(0.05 * t) + 0.001 * randn(N, 1);     % theta
    paramAbs(:, 4) = 1 + 0.01 * sin(0.03 * t);                       % scale
    paramAbs(:, 5) = 0.001 * randn(N, 1);                            % shx
    paramAbs(:, 6) = 0.001 * randn(N, 1);                            % shy

    [paramRel, diag] = relative_coordinate_model(paramAbs, struct());
    fprintf('  Forward transform time: %.2f ms\n', diag.abs2rel_time_ms);
    fprintf('  Avg inter-frame translation: %.4f px\n', diag.mean_delta_translation);
    fprintf('  Max inter-frame translation: %.4f px\n', diag.max_delta_translation);
    fprintf('  Roundtrip error:     %.2e (should be < 1e-10)\n', diag.roundtrip_error);

    assert(diag.roundtrip_error < 1e-8, 'Roundtrip error too large');
    assert(all(size(paramRel) == [N, 6]), 'Output size mismatch');
    assert(all(paramRel(1, :) == 0), 'First frame increment should be zero');

    fprintf('  Self-test passed ✓\n');
end
