# This file is a part of Julia. License is MIT: https://julialang.org/license

using Test
isdefined(Main, :OffsetArrays) || @eval Main include("testhelpers/OffsetArrays.jl")
using .Main.OffsetArrays
isdefined(Main, :TSlow) || @eval Main include("testhelpers/arrayindexingtypes.jl")
using .Main: TSlow, WrapperArray

tslow(a::AbstractArray) = TSlow(a)
wrapper(a::AbstractArray) = WrapperArray(a)
fcviews(a::AbstractArray) = view(a, ntuple(Returns(:),ndims(a)-1)..., axes(a)[end])
fcviews(a::AbstractArray{<:Any, 0}) = view(a)
offset_nominal(a::AbstractArray) = OffsetArray(a)
offset_maybe(a::AbstractArray) = (eltype(a) <: Real) ? a : OffsetArray(a, (1-ndims(A)):2:(ndims(A)-1)...)
tslow(t::Tuple) = map(tslow, t)
wrapper(t::Tuple) = map(wrapper, t)
fcviews(t::Tuple) = map(fcviews, t)
offset_nominal(t::Tuple) = map(offset_nominal, t)
offset_maybe(t::Tuple) = map(offset_maybe, t)

test_many_wrappers(testf, A, wrappers) = foreach(w -> testf(w(A)), wrappers)
test_many_wrappers(testf, A) = test_many_wrappers(
    testf, A, (identity, tslow, wrapper, fcviews, offset_nominal, offset_maybe)
)

A = Int64[1, 2, 3, 4]
Ars = Int64[1 3; 2 4]
B = Complex{Int64}[5+6im, 7+8im, 9+10im]
Av = [Int32[1,2], Int32[3,4]]
C = view([1,1], [1,2])

test_many_wrappers(Ars, (identity, tslow)) do Ar
    @test @inferred(ndims(reinterpret(reshape, Complex{Int64}, Ar))) == 1
    @test @inferred(axes(reinterpret(reshape, Complex{Int64}, Ar))) === (Base.OneTo(2),)
    @test @inferred(size(reinterpret(reshape, Complex{Int64}, Ar))) == (2,)
end
test_many_wrappers(B, (identity, tslow)) do _B
    @test @inferred(ndims(reinterpret(reshape, Int64, _B))) == 2
    @test @inferred(axes(reinterpret(reshape, Int64, _B))) === (Base.OneTo(2), Base.OneTo(3))
    @test @inferred(size(reinterpret(reshape, Int64, _B))) == (2, 3)
    @test @inferred(ndims(reinterpret(reshape, Int128, _B))) == 1
    @test @inferred(axes(reinterpret(reshape, Int128, _B))) === (Base.OneTo(3),)
    @test @inferred(size(reinterpret(reshape, Int128, _B))) == (3,)
end

@test_throws ArgumentError("cannot reinterpret `Int64` as `Vector{Int64}`, type `Vector{Int64}` is not a bits type") reinterpret(Vector{Int64}, A)
@test_throws ArgumentError("cannot reinterpret `Vector{Int32}` as `Int32`, type `Vector{Int32}` is not a bits type") reinterpret(Int32, Av)
@test_throws ArgumentError("cannot reinterpret a zero-dimensional `Int64` array to `Int32` which is of a different size") reinterpret(Int32, reshape([Int64(0)]))
@test_throws ArgumentError("cannot reinterpret a zero-dimensional `Int32` array to `Int64` which is of a different size") reinterpret(Int64, reshape([Int32(0)]))
@test_throws ArgumentError("cannot reinterpret an `$Int` array to `Tuple{$Int, $Int}` whose first dimension has size `5`."*
                              " The resulting array would have a non-integral first dimension.") reinterpret(Tuple{Int,Int}, [1,2,3,4,5])

@test_throws ArgumentError("`reinterpret(reshape, Complex{Int64}, a)` where `eltype(a)` is Int64 requires that `axes(a, 1)` (got Base.OneTo(4)) be equal to 1:2 (from the ratio of element sizes)") reinterpret(reshape, Complex{Int64}, A)
@test_throws ArgumentError("`reinterpret(reshape, T, a)` requires that one of `sizeof(T)` (got 24) and `sizeof(eltype(a))` (got 16) be an integer multiple of the other") reinterpret(reshape, NTuple{3, Int64}, B)
@test_throws ArgumentError("cannot reinterpret `Int64` as `Vector{Int64}`, type `Vector{Int64}` is not a bits type") reinterpret(reshape, Vector{Int64}, Ars)
@test_throws ArgumentError("cannot reinterpret a zero-dimensional `UInt8` array to `UInt16` which is of a larger size") reinterpret(reshape, UInt16, reshape([0x01]))

# getindex
test_many_wrappers(A) do _A
    @test reinterpret(Complex{Int64}, _A) == [1 + 2im, 3 + 4im]
    @test reinterpret(Float64, _A) == reinterpret.(Float64, A)
    @test reinterpret(reshape, Float64, _A) == reinterpret.(Float64, A)
end
test_many_wrappers(Ars) do Ar
    @test reinterpret(reshape, Complex{Int64}, Ar) == [1 + 2im, 3 + 4im]
    @test reinterpret(reshape, Float64, Ar) == reinterpret.(Float64, Ars)
end

test_many_wrappers(B) do _B
    @test reinterpret(NTuple{3, Int64}, _B) == [(5,6,7),(8,9,10)]
    @test reinterpret(reshape, Int64, _B) == [5 7 9; 6 8 10]
end

@testset "setindex! converts before reinterpreting" begin
    for dims in ((), 1)
        z = reinterpret(UInt64, fill(1.0, dims))
        @test z[] == z[1] == 0x3ff0000000000000
        z[] = Int32(1)//Int32(1)
        @test z[] == z[1] == 0x0000000000000001
        z[1] = Int32(2)//Int32(1)
        @test z[] == z[1] == 0x0000000000000002
        z[1] = 3//1
        @test z[] == z[1] == 0x0000000000000003
        @test_throws InexactError z[] = 3//2
        @test_throws InexactError z[] = 1.5
        @test_throws InexactError z[1] = 3//2
        @test_throws InexactError z[1] = 1.5

        z = reinterpret(UInt64, fill(Int32(16)//Int32(1), dims))
        @test z[] == z[1] == 0x0000000100000010
        z[] = Int32(1)//Int32(1)
        @test z[] == z[1] == 0x0000000000000001
        z[1] = Int32(2)//Int32(1)
        @test z[] == z[1] == 0x0000000000000002
        z[1] = 3//1
        @test z[] == z[1] == 0x0000000000000003
        @test_throws InexactError z[] = 3//2
        @test_throws InexactError z[] = 1.5
        @test_throws InexactError z[1] = 3//2
        @test_throws InexactError z[1] = 1.5

        z = reinterpret(Missing, fill(nothing, dims))
        @test z[] === missing
        @test z[1] === missing
        @test_throws "cannot convert" z[] = nothing
        @test_throws "cannot convert" z[1] = nothing
        @test z[] === missing
        @test z[1] === missing
    end
end

# setindex
test_many_wrappers((A, Ars, B)) do (A, Ars, B)
    _A, Ar, _B = deepcopy(A), deepcopy(Ars), deepcopy(B)
    let Ac = deepcopy(_A), Arsc = deepcopy(Ar), Bc = deepcopy(_B)
        reinterpret(Complex{Int64}, Ac)[2] = -1 - 2im
        @test Ac == [1, 2, -1, -2]
        reinterpret(Complex{Int64}, Arsc)[2] = -1 - 2im
        @test Arsc == [1 -1; 2 -2]
        reinterpret(NTuple{3, Int64}, Bc)[2] = (4,5,6)
        @test Bc == Complex{Int64}[5+6im, 7+4im, 5+6im]
        B2 = reinterpret(NTuple{3, Int64}, Bc)
        @test setindex!(B2, (1,2,3), 1) === B2
        @test Bc == Complex{Int64}[1+2im, 3+4im, 5+6im]
        Bc = copy(_B)
        Brrs = reinterpret(reshape, Int64, Bc)
        @test setindex!(Brrs, -5, 2, 3) === Brrs
        @test Bc == Complex{Int64}[5+6im, 7+8im, 9-5im]
        Brrs[last(eachindex(Brrs))] = 22
        @test Bc == Complex{Int64}[5+6im, 7+8im, 9+22im]

        A1 = reinterpret(Float64, _A)
        A2 = reinterpret(ComplexF64, _A)
        @test setindex!(A1, 1.0, 1) === A1
        @test real(A2[1]) == 1.0
        A1 = reinterpret(reshape, Float64, _A)
        @test setindex!(A1, 2.5, 1) === A1
        @test reinterpret(Float64, _A[1]) == 2.5
        A1rs = reinterpret(Float64, Ar)
        A2rs = reinterpret(ComplexF64, Ar)
        @test setindex!(A1rs, 1.0, 1, 1) === A1rs
        @test real(A2rs[1]) == 1.0
        A1rs = reinterpret(reshape, Float64, Ar)
        A2rs = reinterpret(reshape, ComplexF64, Ar)
        @test setindex!(A1rs, 2.5, 1, 1) === A1rs
        @test real(A2rs[1]) == 2.5
    end
end
A3 = collect(reshape(1:18, 2, 3, 3))
test_many_wrappers(A3) do A3_
    A3 = deepcopy(A3_)
    A3r = reinterpret(reshape, Complex{Int}, A3)
    @test A3r[4] === A3r[1,2] === A3r[CartesianIndex(1, 2)] === 7+8im
    A3r[2,3] = -8-15im
    @test A3[1,2,3] == -8
    @test A3[2,2,3] == -15
    A3r[4] = 100+200im
    @test A3[1,1,2] == 100
    @test A3[2,1,2] == 200
    A3r[CartesianIndex(1,2)] = 300+400im
    @test A3[1,1,2] == 300
    @test A3[2,1,2] == 400
end

test_many_wrappers(C) do Cr_
    Cr = deepcopy(Cr_)
    r = reinterpret(reshape, Tuple{Int, Int}, Cr)
    @test r == fill((1,1))
    r[] = (2,2)
    @test r[] === (2,2)
    r[1] = (3,3)
    @test r[1] === (3,3)
    r[1,1] = (4,4)
    @test r[1,1] === (4,4)
end

# same-size reinterpret where one of the types is non-primitive
let a = NTuple{4,UInt8}[(0x01,0x02,0x03,0x04)]
    test_many_wrappers(a, (identity, wrapper, fcviews)) do a_
        a = deepcopy(a_)
        ra = reinterpret(Float32, a)
        @test ra[1] == reinterpret(Float32, 0x04030201)
        @test setindex!(ra, 2.0) === ra
        @test reinterpret(Float32, a)[1] == 2.0
    end
end
let a = NTuple{4,UInt8}[(0x01,0x02,0x03,0x04)]
    test_many_wrappers(a, (identity, wrapper, fcviews)) do a_
        a = deepcopy(a_)
        ra = reinterpret(reshape, Float32, a)
        @test ra[1] == reinterpret(Float32, 0x04030201)
        @test setindex!(ra, 2.0) === ra
        @test reinterpret(reshape, Float32, a)[1] == 2.0
    end
end

# Pass-through indexing
B = Complex{Int64}[5+6im, 7+8im, 9+10im]
test_many_wrappers(B) do B_
    B = deepcopy(B_)
    Br = reinterpret(reshape, Int64, B)
    W = WrapperArray(Br)
    for (b, w) in zip(5:10, W)
        @test b == w
    end
    for (i, j) in zip(eachindex(W), 11:16)
        W[i] = j
    end
    @test B[1] === Complex{Int64}(11+12im)
    @test B[2] === Complex{Int64}(13+14im)
    @test B[3] === Complex{Int64}(15+16im)
end
z3 = (0x00, 0x00, 0x00)
Az = [z3 z3; z3 z3]
test_many_wrappers(Az, (identity, wrapper)) do Az_
    Az = deepcopy(Az_)
    Azr = reinterpret(reshape, UInt8, Az)
    W = WrapperArray(Azr)
    copyto!(W, fill(0x01, 3, 2, 2))
    @test all(isequal((0x01, 0x01, 0x01)), Az)
    @test eachindex(W, W) == eachindex(W)
end

# ensure that reinterpret arrays aren't erroneously classified as strided
let A = reshape(1:20, 5, 4)
    V = view(A, :, :)
    R = reinterpret(Int32, V)
    R2 = reinterpret(Int32, A)
    @test !(R isa StridedArray)
    @test !(R2 isa StridedArray)
    @test R * ones(4, 5) == R2 * ones(4,5) == copy(R) * ones(4,5) == copy(R2) * ones(4,5)
end

# but ensure that strided views of strided reinterpret arrays are still strided
let A = collect(reshape(1:20, 5, 4))
    R = reinterpret(Int32, A)
    @test R isa StridedArray
    @test view(R, :, :) isa StridedArray
    @test reshape(R, :) isa StridedArray
end

function check_strides(A::AbstractArray)
    # Make sure stride(A, i) is equivalent with strides(A)[i] (if 1 <= i <= ndims(A))
    dims = ntuple(identity, ndims(A))
    map(i -> stride(A, i), dims) == strides(A) || return false
    # Test strides via value check.
    for i in eachindex(IndexLinear(), A)
        A[i] === Base.unsafe_load(pointer(A, i)) || return false
    end
    return true
end

@testset "strides for NonReshapedReinterpretArray" begin
    A = WrapperArray(Array{Int32}(reshape(1:88, 11, 8)))
    for viewax2 in (1:8, 1:2:6, 7:-1:1, 5:-2:1, 2:3:8, 7:-6:1, 3:5:11)
        # dim1 is contiguous
        for T in (Int16, Float32)
            @test check_strides(reinterpret(T, view(A, 1:8, viewax2)))
        end
        if mod(step(viewax2), 2) == 0
            @test check_strides(reinterpret(Int64, view(A, 1:8, viewax2)))
        else
            @test_throws "Parent's strides" strides(reinterpret(Int64, view(A, 1:8, viewax2)))
        end
        # non-integer-multiplied classified
        if mod(step(viewax2), 3) == 0
            @test check_strides(reinterpret(NTuple{3,Int16}, view(A, 2:7, viewax2)))
        else
            @test_throws "Parent's strides" strides(reinterpret(NTuple{3,Int16}, view(A, 2:7, viewax2)))
        end
        if mod(step(viewax2), 5) == 0
            @test check_strides(reinterpret(NTuple{5,Int16}, view(A, 2:11, viewax2)))
        else
            @test_throws "Parent's strides" strides(reinterpret(NTuple{5,Int16}, view(A, 2:11, viewax2)))
        end
        # dim1 is not contiguous
        for T in (Int16, Int64)
            @test_throws "Parent must" strides(reinterpret(T, view(A, 8:-1:1, viewax2)))
        end
        @test check_strides(reinterpret(Float32, view(A, 8:-1:1, viewax2)))
    end
    # issue 46113
    A = reinterpret(Int8, reinterpret(reshape, Int16, rand(Int8, 2, 3, 3)))
    @test check_strides(A)
end

@testset "strides for ReshapedReinterpretArray" begin
    A = WrapperArray(Array{Int32}(reshape(1:192, 3, 8, 8)))
    for viewax1 in (1:8, 1:2:8, 8:-1:1, 8:-2:1), viewax2 in (1:2, 4:-1:1)
        for T in (Int16, Float32)
            @test check_strides(reinterpret(reshape, T, view(A, 1:2, viewax1, viewax2)))
            @test check_strides(reinterpret(reshape, T, view(A, 1:2:3, viewax1, viewax2)))
        end
        if mod(step(viewax1), 2) == 0
            @test check_strides(reinterpret(reshape, Int64, view(A, 1:2, viewax1, viewax2)))
        else
            @test_throws "Parent's strides" strides(reinterpret(reshape, Int64, view(A, 1:2, viewax1, viewax2)))
        end
        @test_throws "Parent must" strides(reinterpret(reshape, Int64, view(A, 1:2:3, viewax1, viewax2)))
    end
end

@testset "strides" begin
    a = rand(10)
    b = view(a,2:2:10)
    A = rand(10,10)
    B = view(A, 2:2:10, 2:2:10)

    @test strides(a) == (1,)
    @test strides(b) == (2,)
    @test strides(A) == (1,10)
    @test strides(B) == (2,20)

    for M in (a, b, A, B)
        @inferred strides(M)
        strides_M = strides(M)

        for (i, _stride) in enumerate(collect(strides_M))
            @test _stride == stride(M, i)
        end
    end
end

# IndexStyle
test_many_wrappers(fill(1.0, 5, 3), (identity, wrapper)) do a_
    a = deepcopy(a_)
    r = reinterpret(Int64, a)
    @test @inferred(IndexStyle(r)) == IndexLinear()
    fill!(r, 2)
    @test all(a .=== reinterpret(Float64, [Int64(2)])[1])
    @test all(r .=== Int64(2))
    for badinds in ((), 0, 16, (0,1), (1,0), (6,3), (5,4))
        @test_throws BoundsError r[badinds...]
        @test_throws BoundsError r[badinds...] = -2
    end
    for goodinds in (1, 15, (1,1), (5,3))
        @test setindex!(r, -2, goodinds...) === r
        @test r[goodinds...] == -2
    end
    r = reinterpret(Int32, a)
    @test @inferred(IndexStyle(r)) == IndexLinear()
    fill!(r, 3)
    @test all(a .=== reinterpret(Float64, [(Int32(3), Int32(3))])[1])
    @test all(r .=== Int32(3))
    for badinds in ((), 0, 31, (0,1), (1,0), (11,3), (10,4))
        @test_throws BoundsError r[badinds...]
        @test_throws BoundsError r[badinds...] = -3
    end
    for goodinds in (1, 30, (1,1), (10,3))
        @test setindex!(r, -3, goodinds...) === r
        @test r[goodinds...] == -3
    end
    r = reinterpret(Int64, view(a, 1:2:5, :))
    @test @inferred(IndexStyle(r)) == IndexCartesian()
    fill!(r, 4)
    @test all(a[1:2:5,:] .=== reinterpret(Float64, [Int64(4)])[1])
    @test all(r .=== Int64(4))
    for badinds in ((), 0, 10, (0,1), (1,0), (4,3), (3,4))
        @test_throws BoundsError r[badinds...]
        @test_throws BoundsError r[badinds...] = -4
    end
    for goodinds in (1, 9, (1,1), (3,3))
        @test setindex!(r, -4, goodinds...) === r
        @test r[goodinds...] == -4
    end
    r = reinterpret(Int32, view(a, 1:2:5, :))
    @test @inferred(IndexStyle(r)) == IndexCartesian()
    fill!(r, 5)
    @test all(a[1:2:5,:] .=== reinterpret(Float64, [(Int32(5), Int32(5))])[1])
    @test all(r .=== Int32(5))
    for badinds in ((), 0, 19, (0,1), (1,0), (7,3), (6,4))
        @test_throws BoundsError r[badinds...]
        @test_throws BoundsError r[badinds...] = -5
    end
    for goodinds in (1, 18, (1,1), (6,3))
        @test setindex!(r, -5, goodinds...) === r
        @test r[goodinds...] == -5
    end
end

let a = rand(ComplexF32, 5)
    r = reinterpret(reshape, Float32, a)
    ref = Array(r)

    @test all(r .== OffsetArray(r)[:, :, :])

    @test r[1, :, 1]        == ref[1, :]
    @test r[1, :, 1, 1, 1]  == ref[1, :]
    @test r[1, :, UInt8(1)] == ref[1, :]

    r[2, :, 1] .= 0f0
    ref[2,  :] .= 0f0
    @test r[2, :, 1] == ref[2, :]

    @test r[4] == ref[4]
    @test_throws BoundsError r[1, :, 2]
end

let ar = [(1,2), (3,4)]
    arr = reinterpret(reshape, Int, ar)
    @test @inferred(IndexStyle(arr)) == Base.IndexSCartesian2{2}()
    @test @inferred(eachindex(arr)) == Base.SCartesianIndices2{2}(Base.OneTo(2))
    @test @inferred(eachindex(arr, arr)) == Base.SCartesianIndices2{2}(Base.OneTo(2))
end
# Error on reinterprets that would expose padding
struct S1
    a::Int8
    b::Int64
end

struct S2
    a::Int16
    b::Int64
end

A1 = S1[S1(0, 0)]
A2 = S2[S2(0, 0)]
test_many_wrappers((A1, A2), (identity, wrapper)) do (A1_, A2_)
    A1, A2 = deepcopy(A1_), deepcopy(A2_)
    @test reinterpret(S1, A2)[1] == S1(0, 0)
    @test_throws Base.PaddingError (reinterpret(S1, A2)[1] = S2(1, 2))
    @test_throws Base.PaddingError reinterpret(S2, A1)[1]
    reinterpret(S2, A1)[1] = S2(1, 2)
    @test A1[1] == S1(1, 2)
end

# Unconventional axes
let a = [0.1 0.2; 0.3 0.4], at = reshape([(i,i+1) for i = 1:2:8], 2, 2)
    v = OffsetArray(a, (-1, 1))
    r = reinterpret(Int64, v)
    @test axes(r) === axes(v)
    @test r[0,2] === reinterpret(Int64, v[0,2])
    @test r[1,2] === reinterpret(Int64, v[1,2])
    @test r[0,3] === reinterpret(Int64, v[0,3])
    @test r[1,3] === reinterpret(Int64, v[1,3])
    @test_throws ArgumentError("cannot reinterpret a `Float64` array to `UInt32` when the first axis is $(repr(axes(v,1))). Try reshaping first.") reinterpret(UInt32, v)
    @test_throws ArgumentError("`reinterpret(reshape, Tuple{Float64, Float64}, a)` where `eltype(a)` is Float64 requires that `axes(a, 1)` (got $(repr(axes(v,1)))) be equal to 1:2 (from the ratio of element sizes)") reinterpret(reshape, Tuple{Float64,Float64}, v)
    v = OffsetArray(a, (0, 1))
    @test axes(reinterpret(reshape, Tuple{Float64,Float64}, v)) === (OffsetArrays.IdOffsetRange(Base.OneTo(2), 1),)
    r = reinterpret(UInt32, v)
    axsv = axes(v)
    @test axes(r) === (oftype(axsv[1], 1:4), axsv[2])
    for i = 1:2
        rval = reinterpret(Tuple{UInt32,UInt32}, [v[i,2]])[1]
        @test r[2i-1,2]   == rval[1]
        @test r[2i,2] == rval[2]
        rval = reinterpret(Tuple{UInt32,UInt32}, [v[i,3]])[1]
        @test r[2i-1,3]   == rval[1]
        @test r[2i,3] == rval[2]
    end
    r[4,2] = 7
    @test r[4,2] === UInt32(7)
    @test a[2,1] === reinterpret(Float64, [0x33333333, UInt32(7)])[1]
    offsetvt = (-2, 4)
    vt = OffsetArray(at, offsetvt)
    istr = string(Int)
    @test_throws ArgumentError("cannot reinterpret a `Tuple{$istr, $istr}` array to `$istr` when the first axis is $(repr(axes(vt,1))). Try reshaping first.") reinterpret(Int, vt)
    vt = reshape(vt, 1:1, axes(vt)...)
    r = reinterpret(Int, vt)
    @test r == OffsetArray(reshape(1:8, 2, 2, 2), (0, offsetvt...))
end

@testset "potentially aliased copies" begin
    buffer = UInt8[1,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0]
    mid = length(buffer) ÷ 2
    x1 = reinterpret(Int64, @view buffer[1:mid])
    x2 = reinterpret(Int64, @view buffer[mid+1:end])
    x1 .= x2
    @test x1 == x2 == [2]
    @test x1[] === x2[] === Int64(2)
end

# avoid nesting
@test parent(reinterpret(eltype(A), reinterpret(eltype(B), A))) === A

# Test 0-dimensional Arrays
A = zeros(UInt32)
test_many_wrappers(A, (identity, wrapper)) do A_
    A = deepcopy(A_)
    B = reinterpret(Int32, A)
    Brs = reinterpret(reshape,Int32, A)
    C = reinterpret(Tuple{UInt32}, A) # non-primitive type
    Crs = reinterpret(reshape, Tuple{UInt32}, A)  # non-primitive type
    @test size(B) == size(Brs) == size(C) == size(Crs) == ()
    @test axes(B) == axes(Brs) == axes(C) == axes(Crs) == ()
    @test setindex!(B, Int32(5)) === B
    @test B[] === Int32(5)
    @test Brs[] === Int32(5)
    @test C[] === (UInt32(5),)
    @test Crs[] === (UInt32(5),)
    @test A[] === UInt32(5)
    @test setindex!(Brs, Int32(12)) === Brs
    @test A[] === UInt32(12)
    @test setindex!(C, (UInt32(7),)) === C
    @test A[] === UInt32(7)
    @test setindex!(Crs, (UInt32(3),)) === Crs
    @test A[] === UInt32(3)
end

test_many_wrappers([(1.0,2.0)], (identity, wrapper)) do a
    af = @inferred(reinterpret(reshape, Float64, a))
    anew = @inferred(reinterpret(reshape, Tuple{Float64,Float64}, vec(af)))
    @test anew[1] == a[1]
    @test ndims(anew) == 0
end

# re-reinterpret
a0 = reshape([0x22, 0x44, 0x88, 0xf0, 0x01, 0x02, 0x03, 0x04], 4, 2)
test_many_wrappers(a0, (identity, wrapper)) do a0
    a = reinterpret(reshape, NTuple{4,UInt8}, a0)
    @test a == [(0x22, 0x44, 0x88, 0xf0), (0x01, 0x02, 0x03, 0x04)]
    @test reinterpret(UInt8, a) == [0x22, 0x44, 0x88, 0xf0, 0x01, 0x02, 0x03, 0x04]
    @test reinterpret(reshape, UInt8, a) === a0
end

# reductions
a = [(1,2,3), (4,5,6)]
test_many_wrappers(a, (identity, wrapper)) do a
    ars = reinterpret(reshape, Int, a)
    @test sum(ars) == 21
    @test sum(ars; dims=1) == [6 15]
    @test sum(ars; dims=2) == reshape([5,7,9], (3, 1))
    @test sum(ars; dims=(1,2)) == reshape([21], (1, 1))
end
# also test large sizes for the pairwise algorithm
a = [(k,k+1,k+2) for k = 1:3:4000]
test_many_wrappers(a, (identity, wrapper)) do a
    ars = reinterpret(reshape, Int, a)
    @test sum(ars) == 8010003
end

@testset "similar(::ReinterpretArray)" begin
    a = reinterpret(NTuple{2,Float64}, TSlow(rand(Float64, 4, 4)))

    as = similar(a)
    @test as isa TSlow{NTuple{2,Float64},2}
    @test size(as) == (2, 4)

    as = similar(a, Int, (3, 5, 1))
    @test as isa TSlow{Int,3}
    @test size(as) == (3, 5, 1)

    a = reinterpret(reshape, NTuple{4,Float64}, TSlow(rand(Float64, 4, 4)))

    as = similar(a)
    @test as isa TSlow{NTuple{4,Float64},1}
    @test size(as) == (4,)
end


@testset "aliasing" begin
    a = reinterpret(NTuple{2,Float64}, rand(Float64, 4, 4))
    @test typeof(Base.unaliascopy(a)) === typeof(a)
    a = reinterpret(reshape, NTuple{4,Float64}, rand(Float64, 4, 4))
    @test typeof(Base.unaliascopy(a)) === typeof(a)
end


@testset "singleton types" begin
    mutable struct NotASingleton end # not a singleton because it is mutable
    struct SomeSingleton
        # A singleton type that does not have the internal constructor SomeSingleton()
        SomeSingleton(x) = new()
    end

    @test_throws ArgumentError reinterpret(Int, nothing)
    @test_throws ArgumentError reinterpret(Missing, 3)
    @test_throws ArgumentError reinterpret(Missing, NotASingleton())
    @test_throws ArgumentError reinterpret(NotASingleton, ())

    @test_throws ArgumentError reinterpret(NotASingleton, fill(nothing, ()))
    @test_throws ArgumentError reinterpret(reshape, NotASingleton, fill(missing, 3))
    @test_throws ArgumentError reinterpret(Tuple{}, fill(NotASingleton(), 2))
    @test_throws ArgumentError reinterpret(reshape, Nothing, fill(NotASingleton(), ()))

    t = fill(nothing, 3, 5)
    @test reinterpret(SomeSingleton, t) == reinterpret(reshape, SomeSingleton, t)
    @test reinterpret(SomeSingleton, t) == [SomeSingleton(i*j) for i in 1:3, j in 1:5]
    @test reinterpret(Int, t) == fill(17, 0, 5)
    @test_throws ArgumentError reinterpret(reshape, Float64, t)
    @test_throws ArgumentError reinterpret(Nothing, 1:6)
    @test_throws ArgumentError reinterpret(reshape, Missing, [0.0])

    # reinterpret of empty array
    @test reinterpret(reshape, Nothing, fill(missing, (1,0,3))) == fill(nothing, (1,0,3))
    @test reinterpret(reshape, Missing, fill((), (0,))) == fill(missing, (0,))
    @test_throws ArgumentError reinterpret(reshape, Nothing, fill(3.2, (0,0)))
    @test_throws ArgumentError reinterpret(Missing, fill(77, (0,1)))
    @test_throws ArgumentError reinterpret(reshape, Float64, fill(nothing, 0))

    # reinterpret of 0-dimensional array
    z = reinterpret(Tuple{}, fill(missing, ()))
    @test z == fill((), ())
    @test z == reinterpret(reshape, Tuple{}, fill(nothing, ()))
    @test z[] == ()
    @test setindex!(z, ()) === z
    @test_throws BoundsError z[2]
    @test_throws BoundsError z[3] = ()
    @test_throws ArgumentError reinterpret(UInt8, fill(nothing, ()))
    @test_throws ArgumentError reinterpret(Missing, fill(1f0, ()))
    @test_throws ArgumentError reinterpret(reshape, Float64, fill(nothing, ()))
    @test_throws ArgumentError reinterpret(reshape, Nothing, fill(17, ()))
    @test_throws MethodError z[] = nothing

    @test @inferred(ndims(reinterpret(reshape, SomeSingleton, t))) == 2
    @test @inferred(axes(reinterpret(reshape, Tuple{}, t))) == (Base.OneTo(3),Base.OneTo(5))
    @test @inferred(size(reinterpret(reshape, Missing, t))) == (3,5)

    x = reinterpret(Tuple{}, t)
    @test x == reinterpret(reshape, Tuple{}, t)
    @test x[3,5] === ()
    x1 = fill((), 3, 5)
    @test setindex!(x, (), 1, 1) == x1
    @test_throws BoundsError x[17]
    @test_throws BoundsError x[4,2]
    @test_throws BoundsError x[1,2,3]
    @test_throws BoundsError x[18] = ()
    @test_throws MethodError x[1,3] = missing
    @test x == fill((), (3, 5))
    x = reinterpret(reshape, SomeSingleton, t)
    @test_throws BoundsError x[19]
    @test_throws BoundsError x[2,6] = SomeSingleton(0xa)
    @test x[2,3] === SomeSingleton(:x)
    x2 = fill(SomeSingleton(0.7), 3, 5)
    @test x == x2
    @test setindex!(x, SomeSingleton(:), 3, 5) == x2
    @test_throws MethodError x[2,4] = nothing
end

@testset "pointer for StridedArray" begin
    a = rand(Float64, 251)
    v = view(a, UInt(2):UInt(251));
    A = reshape(v, 25, 10);
    @test A isa StridedArray && pointer(A) === pointer(a, 2)
    Av = view(A, 1:20, 1:2)
    @test Av isa StridedArray && pointer(Av) === pointer(a, 2)
    @test Av * Av' isa Array
end

@testset "effect of StridedReinterpretArray's getindex" begin
    eff = Base.infer_effects(getindex, Base.typesof(reinterpret(Int8, Int[1]), 1))
    @test Core.Compiler.is_effect_free(eff)
end

# reinterpret of arbitrary bitstypes
@testset "Reinterpret arbitrary bitstypes" begin
    struct Bytes15
        a::Int8
        b::Int16
        c::Int32
        d::Int64
    end

    @test reinterpret(Float64, ComplexF32(1, 1)) === 0.007812501848093234
    @test reinterpret(ComplexF32, 0.007812501848093234) === ComplexF32(1, 1)
    @test reinterpret(Tuple{Float64, Float64}, ComplexF64(1, 1)) === (1.0, 1.0)
    @test reinterpret(ComplexF64, (1.0, 1.0)) === ComplexF64(1, 1)
    @test reinterpret(Tuple{Int8, Int16, Int32, Int64}, (Int64(1), Int32(2), Int16(3), Int8(4))) === (Int8(1), Int16(0), Int32(0), 288233674686595584)
    @test reinterpret(Tuple{Int8, Int16, Tuple{Int32, Int64}}, (Int64(1), Int32(2), Int16(3), Int8(4))) === (Int8(1), Int16(0), (Int32(0), 288233674686595584))
    @test reinterpret(Tuple{Int64, Int32, Int16, Int8}, (Int8(1), Int16(0), (Int32(0), 288233674686595584))) === (Int64(1), Int32(2), Int16(3), Int8(4))
    @test reinterpret(Tuple{Int8, Int16, Int32, Int64}, Bytes15(Int8(1), Int16(2), Int32(3), Int64(4))) === (Int8(1), Int16(2), Int32(3), Int64(4))
    @test reinterpret(Bytes15, (Int8(1), Int16(2), Int32(3), Int64(4))) == Bytes15(Int8(1), Int16(2), Int32(3), Int64(4))

    @test_throws ArgumentError reinterpret(Tuple{Int32, Int64}, (Int16(1), Int64(4)))
end

let R = reinterpret(Float32, ComplexF32[1.0f0+2.0f0*im, 4.0f0+3.0f0*im])
    @test !isassigned(R, 0)
    @test isassigned(R, 1)
    @test isassigned(R, 4)
    @test isassigned(R, Int8(2), Int16(1), Int32(1), Int64(1))
    @test !isassigned(R, 1, 2)
    @test !isassigned(R, 5)
    @test Array(R)::Vector{Float32} == [1.0f0, 2.0f0, 4.0f0, 3.0f0]
end

let R = reinterpret(reshape, Float32, ComplexF32[1.0f0+2.0f0*im, 4.0f0+3.0f0*im])
    @test !isassigned(R, 0)
    @test isassigned(R, 1)
    @test isassigned(R, 4)
    @test isassigned(R, Int8(2), Int16(2), Int32(1), Int64(1))
    @test !isassigned(R, 1, 1, 2)
    @test !isassigned(R, 5)
    @test Array(R)::Matrix{Float32} == [1.0f0 4.0f0; 2.0f0 3.0f0]
end

@testset "issue #54623" begin
    x = 0xabcdef01234567
    @test reinterpret(reshape, UInt8, fill(x)) == [0x67, 0x45, 0x23, 0x01, 0xef, 0xcd, 0xab, 0x00]
    @test reinterpret(reshape, UInt8, [x]) == [0x67; 0x45; 0x23; 0x01; 0xef; 0xcd; 0xab; 0x00;;]
end
