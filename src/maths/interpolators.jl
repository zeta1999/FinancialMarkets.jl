###############################################################################
# Types
###############################################################################

# Source:
# Piecewise Polynomial Interpolation, Opengamma (v1, 2013)
# http://www.opengamma.com/blog/piecewise-polynomial-interpolation
abstract Interpolators
abstract Interpolators1D <: Interpolators
abstract SplineInterpolators <: Interpolators1D
immutable LinearSpline <: SplineInterpolators end
abstract CubicSpline <: SplineInterpolators
immutable ClampedCubicSpline <: CubicSpline
    α::Real
    β::Real
end
ClampedCubicSpline() = ClampedCubicSpline(0, 0)
immutable NaturalCubicSpline <: CubicSpline end
immutable NotAKnotCubicSpline <: CubicSpline end
abstract HermiteSplines <: SplineInterpolators
immutable AkimaSpline <: HermiteSplines end
immutable KrugerSpline <: HermiteSplines end

abstract Interpolation
abstract Interpolation1D <: Interpolation
immutable SplineInterpolation <: Interpolation1D
    x::Vector{Real}
    y::Vector{Real}
    coefficients::Matrix{Real}
    function SplineInterpolation(x, y, coefficients)
        msg = "x and y must be the same length"
        length(x) != length(y) || ArgumentError(msg)
        msg = "x must be sorted"
        issorted(x) || ArgumentError(msg)
        new(x, y, coefficients)
    end
end

###############################################################################
# Methods
###############################################################################

function interpolate{T<:Real, S<:Real}(x_new::Real, x::Vector{T}, y::Vector{S},
    i::Interpolators)
    msg = "x_new is not in the interpolator's domain"
    x[1] <= x_new <= x[end] || throw(ArgumentError(msg))
    interpolate(x_new, calibrate(x, y, i))
end

function interpolate(x_new::Real, i::SplineInterpolation)
    msg = "x_new is not in the interpolator's domain"
    i.x[1] <= x_new <= i.x[end] || throw(ArgumentError(msg))
    index = searchsortedlast(i.x, x_new)
    index == length(i.x) && (index = size(i.coefficients)[1])
    polyval(Poly(vec(i.coefficients[index, :])), (x_new - i.x[index]))
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S}, i::LinearSpline)
    SplineInterpolation(x, y, hcat(y[1:(end-1)], diff(y) ./ diff(x)))
end

function calibrate_cubic_spline{T<:Real, S<:Real, U<:Real, V<:Real}(
    x::Vector{T}, y::Vector{S}, A::SparseMatrixCSC{U}, b::Vector{V})
    m = A \ b
    h = diff(x)
    s = diff(y) ./ diff(x)
    mdiff = diff(m)
    mpop = m[1:(end-1)]
    a0 = y[1:(end-1)]
    a1 = s - h.*mpop / 2 - h.*mdiff / 6
    a2 = mpop / 2
    a3 = mdiff ./ h / 6
    SplineInterpolation(x, y, hcat(a0, a1, a2, a3))
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S},
    i::ClampedCubicSpline)
    h = diff(x)
    s = diff(y) ./ h
    diag = [2h[1], [2(h[i] + h[i+1]) for i=1:(length(h)-1)], 2h[end]]
    A = spdiagm((h, diag, h), (-1, 0, 1))
    b = 6 * [s[1] - i.α, diff(s), i.β - s[end]]
    calibrate_cubic_spline(x, y, A, b)
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S},
    i::NaturalCubicSpline)
    h = diff(x)
    s = diff(y) ./ h
    diag_left = [h[1:(end-1)], 0]
    diag = [1, [2(h[i] + h[i+1]) for i=1:(length(h)-1)], 1]
    diag_right = [0, h[2:end]]
    A = spdiagm((diag_left, diag, diag_right), (-1, 0, 1))
    b = 6 * [0, diff(s), 0]
    calibrate_cubic_spline(x, y, A, b)
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S},
    i::NotAKnotCubicSpline)
    h = diff(x)
    s = diff(y) ./ h
    diag_l2 = [zeros(x[4:end]), -h[end]]
    diag_l1 = [h[1:(end-1)], h[end-1] + h[end]]
    diag = [-h[2], [2(h[i] + h[i+1]) for i=1:(length(h)-1)], -h[end-1]]
    diag_r1 = [h[1] + h[2], h[2:end]]
    diag_r2 = [-h[1], zeros(x[4:end])]
    A = spdiagm((diag_l2, diag_l1, diag, diag_r1, diag_r2), (-2, -1, 0, 1, 2))
    b = 6 * [0, diff(s), 0]
    calibrate_cubic_spline(x, y, A, b)
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S}, i::AkimaSpline)
    # Also using:
    # http://www.iue.tuwien.ac.at/phd/rottinger/node60.html
    N = length(x)
    h = diff(x)
    s = diff(y) ./ h
    s0 = 2s[1] - s[2]
    sm1 = 2s0 - s[1]
    sk = 2s[end] - s[end-1]
    skp1 = 2sk - s[end]
    sext = [sm1, s0, s, sk, skp1]
    sd = abs(diff(sext))
    yd = zeros(x)
    for i = 1:N
        if sd[i+2] == 0 && sd[i] == 0
            yd[i] = (sext[i+1] + sext[i+2]) / 2
        else
            yd[i] = (sd[i+2] * sext[i+1] + sd[i] * sext[i+2]) / (sd[i+2] + sd[i])
        end
    end
    a0 = y[1:end-1]
    a1 = yd[1:end-1]
    a2 = [(3s[i] - yd[i+1] - 2yd[i]) / h[i] for i=1:length(s)]
    a3 = [-(2s[i] - yd[i+1] - yd[i]) / h[i]^2 for i=1:length(s)]
    SplineInterpolation(x, y, hcat(a0, a1, a2, a3))
end

function calibrate{T<:Real, S<:Real}(x::Vector{T}, y::Vector{S}, i::KrugerSpline)
    # The constrained cubic spline
    N = length(x)
    h = diff(x)
    s = diff(y) ./ h
    yd = zeros(x)
    for i=2:N-1
        sign_changed = s[i-1]s[i] <= 0
        sign_changed && (yd[i] = 2 / (1 / s[i-1] + 1/s[i]))
        sign_changed || (yd[i] = 0)
    end
    yd[1] = 1.5s[1] - 0.5yd[2]
    yd[end] = 1.5s[end] - 0.5yd[end-1]
    a0 = y[1:end-1]
    a1 = yd[1:end-1]
    a2 = [(3s[i] - yd[i+1] - 2yd[i]) / h[i] for i=1:length(s)]
    a3 = [-(2s[i] - yd[i+1] - yd[i]) / h[i]^2 for i=1:length(s)]
    SplineInterpolation(x, y, hcat(a0, a1, a2, a3))
end
