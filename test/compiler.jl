@testset "compiler" begin

eqs = [:(foo(0) = log(a(0))+b(0)/x(-1)), :(bar(0) = c(1)+u*d(1))]
args = [(:a, -1), (:a, 0), (:b, 0), (:c, 0), (:c, 1), (:d, 1)]
params = [:u]
defs = Dict(:x=>:(a(0)/(1-c(1))))
targets = [(:foo, 0), (:bar, 0)]
funname = :myfun

flat_args = [(:a, 0), (:b, 1), (:c, -1)]
grouped_args = OrderedDict(:x=>[(:a, -1),], :y=>[(:a, 0), (:b, 0), (:c, 0)], :z=>[(:c, 1), (:d, 1)])
flat_params = [:beta, :delta]
grouped_params = Dict(:p => [:u])

args2 = vcat(args, targets)::Vector{Tuple{Symbol,Int}}

ff = Dolang.FunctionFactory(eqs, args, params, targets=targets, defs=defs,
                            funname=funname)

# no targets
ffnt = Dolang.FunctionFactory(eqs, args2, params, defs=defs, funname=funname)

# with dispatch
ffd = Dolang.FunctionFactory(Int, eqs, args, params, targets=targets,
                             defs=defs, funname=funname)

ff_grouped = let
    _eqs = [
        :(chi*n(0)^eta*c(0)^sigma - w(0)),
        :(1 - beta*(c(0)/c(1))^(sigma)*(1-delta+rk(1)))
    ]

    _defs = Dict(
        :y => :(exp(z(0))*k(0)^alpha*n(0)^(1-alpha)),
        :c => :(y(0) - i(0)),
        :rk => :(alpha*y(0)/k(0)),
        :w => :((1-alpha)*y(0)/n(0)),
    )

    _args = DataStructures.OrderedDict(
        :m => [(:z, 0), (:z2, 0)],
        :s => [(:k, 0)],
        :x => [(:n, 0), (:i, 0)],
        :M => [(:z, 1), (:z2, 1)],
        :S => [(:k, 1)],
        :X => [(:n, 1), (:i, 1)]
    )
    _params = [:beta, :sigma, :eta, :chi, :delta, :alpha, :rho, :zbar, :sig_z]
    FunctionFactory(_eqs, _args, _params, defs=_defs)
end


@testset " _unpack_expr" begin
    nms = [:a, :b, :c]
    have = Dolang._unpack_expr(nms, :V)
    @test have.head == :block
    @test have.args[1] == :(_a_ = Dolang._unpack_var(V, 1))
    @test have.args[2] == :(_b_ = Dolang._unpack_var(V, 2))
    @test have.args[3] == :(_c_ = Dolang._unpack_var(V, 3))

    d = OrderedDict(:x=>nms, :y=>[:d])
    have = Dolang._unpack_expr(d, :V)
    @test have.head == :block
    @test length(have.args) == 2

    have1 = have.args[1]
    @test have1.head == :block
    @test have1.args[1] == :(_a_ = Dolang._unpack_var(x, 1))
    @test have1.args[2] == :(_b_ = Dolang._unpack_var(x, 2))
    @test have1.args[3] == :(_c_ = Dolang._unpack_var(x, 3))

    have2 = have.args[2]
    @test have2.head == :block
    @test have2.args[1] == :(_d_ = Dolang._unpack_var(y, 1))
end

@testset " _unpack_+?(::FunctionFactory)" begin
    ordered_args = [(:c, 1), (:d, 1), (:a, 0), (:b, 0), (:c, 0), (:a, -1)]
    @test Dolang.arg_block(ff, :V) == Dolang._unpack_expr(args, :V)
    @test Dolang.param_block(ff, :p) == Dolang._unpack_expr(params, :p)
end

@testset " _assign_var_expr" begin
    want = :(Dolang._assign_var(out, $Inf, 1))
    @test Dolang._assign_var_expr(:out, Inf, 1) == want

    want = :(Dolang._assign_var(z__m_1, 0, foo))
    @test Dolang._assign_var_expr(:z__m_1, 0, :foo) == want
end

@testset " equation_block" begin
    have = Dolang.equation_block(ff)
    @test have.head == :block
    @test length(have.args) == 4
    @test have.args[1] == :(_foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_)))
    @test have.args[2] == :(_bar__0_ = _c__1_ + _u_ * _d__1_)
    @test have.args[3] == :(Dolang._assign_var(out, _foo__0_, 1))
    @test have.args[4] == :(Dolang._assign_var(out, _bar__0_, 2))

    # now test without targets
    have = Dolang.equation_block(ffnt)
    @test have.head == :block
    @test length(have.args) == 2

    ex1 = :(log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_)) - _foo__0_)
    ex2 = :(_c__1_ + _u_ * _d__1_ - _bar__0_)
    @test have.args[1] == :(Dolang._assign_var(out, $ex1, 1))
    @test have.args[2] == :(Dolang._assign_var(out, $ex2, 2))
end

@testset " allocate_block" begin
    have = Dolang.allocate_block(ff)
    want = :(out = Dolang._allocate_out(eltype(V), 2, V))
    @test have == want
end

@testset " sizecheck_block" begin
    have = Dolang.sizecheck_block(ff)
    want = quote
        expected_size = Dolang._output_size(2, V)
        if size(out) != expected_size
            msg = "Expected out to be size $(expected_size), found $(size(out))"
            throw(DimensionMismatch(msg))
        end
    end

    # remove :line blocks from want
    Dolang._filter_lines!(want)
    @test have == want
end

@testset " (arg|param)_names" begin
    @test [:V] == @inferred Dolang.arg_names(ff)
    @test [:p] == @inferred Dolang.param_names(ff)
end

@testset " signature!?" begin
    @test Dolang.signature(ff) == :(myfun(::Dolang.TDer{0},V::AbstractVector,p))
    @test Dolang.signature!(ff) == :(myfun!(::Dolang.TDer{0},out,V::AbstractVector,p))

    @test Dolang.signature(ffnt) == :(myfun(::Dolang.TDer{0},V::AbstractVector,p))
    @test Dolang.signature!(ffnt) == :(myfun!(::Dolang.TDer{0},out,V::AbstractVector,p))

    # NOTE: I need to escape the Int here so that it will refer to the exact
    #       same int inside ffd
    # @test Dolang.signature(ffd) == :(myfun(::Dolang.TDer{0},::$(Int),V::AbstractVector,p))
    # @test Dolang.signature!(ffd) == :(myfun!(::Dolang.TDer{0},::$(Int),out,V::AbstractVector,p))
end

@testset " compiling functions" begin
    want = Dolang._filter_lines!(:(begin
        function myfun(::Dolang.TDer{0},V::AbstractVector,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
        function myfun(V::AbstractVector,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
    end))

    want_vec = Dolang._filter_lines!(:(begin
        function myfun(::Dolang.TDer{0},V::AbstractArray,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                nrow = size(out,1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),__out__row, __V__row, p)
                end
                return out
            end
        end
        function myfun(V::AbstractArray,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                nrow = size(out,1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),__out__row, __V__row, p)
                end
                return out
            end
        end
    end
    ))

    want! = Dolang._filter_lines!(:(begin
        function myfun!(::Dolang.TDer{0},out,V::AbstractVector,p)
            begin
                expected_size = Dolang._output_size(2, V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
        function myfun!(out,V::AbstractVector,p)
            begin
                expected_size = Dolang._output_size(2, V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
    end))

    want!_vec = Dolang._filter_lines!(:(begin
        function myfun!(::Dolang.TDer{0},out,V::AbstractArray,p)
            begin
                expected_size = Dolang._output_size(2,V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                nrow = size(out,1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),__out__row, __V__row, p)
                end
                return out
            end
        end
        function myfun!(out,V::AbstractArray,p)
            begin
                expected_size = Dolang._output_size(2,V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                nrow = size(out,1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),__out__row, __V__row, p)
                end
                return out
            end
        end
    end
    ))

    want_d = Dolang._filter_lines!(:(begin
        function myfun(::Dolang.TDer{0},$(Dolang.DISPATCH_ARG)::$(Int),V::AbstractVector,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
        function myfun($(Dolang.DISPATCH_ARG)::$(Int),V::AbstractVector,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
    end))

    want_d_vec = Dolang._filter_lines(:(begin
        function myfun(::Dolang.TDer{0},$(Dolang.DISPATCH_ARG)::$(Int),V::AbstractArray,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                nrow = size(out, 1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),$(Dolang.DISPATCH_ARG)::$(Int), __out__row, __V__row, p)
                end
                return out
            end
        end
        function myfun($(Dolang.DISPATCH_ARG)::$(Int),V::AbstractArray,p)
            out = Dolang._allocate_out(eltype(V),2,V)
            begin
                nrow = size(out, 1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),$(Dolang.DISPATCH_ARG)::$(Int), __out__row, __V__row, p)
                end
                return out
            end
        end
    end))

    want_d! = Dolang._filter_lines!(:(begin
        function myfun!(::Dolang.TDer{0},$(Dolang.DISPATCH_ARG)::($Int),out,V::AbstractVector,p)
            begin
                expected_size = Dolang._output_size(2, V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
        function myfun!($(Dolang.DISPATCH_ARG)::($Int),out,V::AbstractVector,p)
            begin
                expected_size = Dolang._output_size(2, V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                begin
                    _u_ = Dolang._unpack_var(p,1)
                end
                begin
                    _a_m1_ = Dolang._unpack_var(V,1)
                    _a__0_ = Dolang._unpack_var(V,2)
                    _b__0_ = Dolang._unpack_var(V,3)
                    _c__0_ = Dolang._unpack_var(V,4)
                    _c__1_ = Dolang._unpack_var(V,5)
                    _d__1_ = Dolang._unpack_var(V,6)
                end
                begin
                    _foo__0_ = log(_a__0_) + _b__0_ / (_a_m1_ / (1 - _c__0_))
                    _bar__0_ = _c__1_ + _u_ * _d__1_
                    Dolang._assign_var(out,_foo__0_,1)
                    Dolang._assign_var(out,_bar__0_,2)
                end
                return out
            end
        end
    end))

    want_d!_vec = Dolang._filter_lines(:(begin
        function myfun!(::Dolang.TDer{0},$(Dolang.DISPATCH_ARG)::$(Int),out,V::AbstractArray,p)
            begin
                expected_size = Dolang._output_size(2,V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                nrow = size(out, 1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),$(Dolang.DISPATCH_ARG)::$(Int), __out__row, __V__row, p)
                end
                return out
            end
        end
        function myfun!($(Dolang.DISPATCH_ARG)::$(Int),out,V::AbstractArray,p)
            begin
                expected_size = Dolang._output_size(2,V)
                if size(out) != expected_size
                    msg = "Expected out to be size $(expected_size), found $(size(out))"
                    throw(DimensionMismatch(msg))
                end
            end
            begin
                nrow = size(out, 1)
                for _row = 1:nrow
                    __out__row = view(out, _row, :)
                    __V__row = Dolang._unpack_obs(V, _row)
                    myfun!($(Dolang.Der{0}),$(Dolang.DISPATCH_ARG)::$(Int), __out__row, __V__row, p)
                end
                return out
            end
        end
    end))


    @testset "  _build_function!?" begin
        @test want == Dolang.build_function(ff, Der{0})
        @test want! == Dolang.build_function!(ff, Der{0})
        @test want_d == Dolang.build_function(ffd, Der{0})
        @test want_d! == Dolang.build_function!(ffd, Der{0})

        @test want_vec == Dolang.build_vec_function(ff, Der{0})
        @test want!_vec == Dolang.build_vec_function!(ff, Der{0})
        @test want_d_vec == Dolang.build_vec_function(ffd, Der{0})
        @test want_d!_vec == Dolang.build_vec_function!(ffd, Der{0})
    end

    @testset "evaluating compiled code" begin
        # prep convenience make_function method arguments
        variables = vcat(args, :u)
        to_diff = 1:length(args)
        conv_code = make_function(eqs, variables, to_diff, name=:anon, targets=targets, defs=defs)
        Core.eval(@__MODULE__, conv_code)
        Core.eval(@__MODULE__, Dolang.make_function(ff))
        for (fun, fun!) in [(myfun, myfun!), (anon, anon!)]
            u = rand()
            V = rand(6) .+ 4
            am, a, b, c, cp, dp = V
            p = [u]

            want = [log(a) + b/(am / (1-c)), cp + u*dp]
            out = similar(want)

            # test scalar, allocating version
            @test want ≈ @inferred fun(V, p)
            @test want ≈ @inferred fun(Dolang.Der{0}, V, p)

            # test scalar, mutating version
            fun!(out, V, p)
            @test want ≈ out

            fun!(Dolang.Der{0}, out, V, p)
            @test want ≈ out

            # test vectorized version
            Vmat = repeat(V', 40, 1)
            @test maximum(abs, want' .- fun(Vmat, p)) < 1e-15
            @test maximum(abs, want' .- fun(Dolang.Der{0}, Vmat, p)) < 1e-15

            # test vectorized mutating version
            out_mat = Array{Float64}(undef, 40, 2)
            fun!(out_mat, Vmat, p)
            @test maximum(abs, want' .- out_mat) < 1e-15

            fun!(Dolang.Der{0}, out_mat, Vmat, p)
            @test maximum(abs, want' .- out_mat) < 1e-15

            ## Now test derivative code!
            want = zeros(Float64, 2, 6)
            want[1, 1] = -1 * b *(1-c)/ (am*am)  # ∂foo/∂am
            want[1, 2] = 1/a  # ∂foo/∂a
            want[1, 3] = (1-c) / (am)  # ∂foo/∂b
            want[1, 4] = -b/am  # ∂foo/∂b
            want[2, 5] = 1.0  # ∂bar/∂cp
            want[2, 6] = u # # ∂bar/∂dp

            # allocating version
            @test want ≈ @inferred fun(Der{1}, V, p)

            # non-alocating version
            out2 = similar(want)
            fun!(Der{1}, out2, V, p)
            @test want ≈ out2

            # and second derivative code
            want = zeros(Float64, 2, 6*6)
            want[1, 1]  = 2 * b * (1-c) / (am^3) # ∂²foo/∂am²   = (1,1)
            want[1, 3]  = -1 *(1-c)/ (am*am)     # ∂²foo/∂am ∂b = (1,3)
            want[1, 4]  = b /(am^2)              # ∂²foo/∂am ∂c = (1,4)
            want[1, 8]  = -1/(a^2)               # ∂²foo/∂a²    = (2,2)
            want[1, 13] = -(1-c)/(am^2)          # ∂²foo/∂b ∂am = (3,1)
            want[1, 16] = -1/am                  # ∂²foo/∂b ∂c  = (3,4)
            want[1, 19] = b/(am^2)               # ∂²foo/∂c ∂am = (4,1)
            want[1, 21] = -1/am                  # ∂²foo/∂c ∂b  = (4,3)

            @test want ≈ @inferred fun(Der{2}, V, p)

            # and third derivative code
            want = [Dict{NTuple{3,Int},Float64}(), Dict{NTuple{3,Int},Float64}()]
            want[1][(1, 1, 1)] = -6 * b * (1-c) / (am^4) # ∂³foo/∂am³
            want[1][(1, 1, 3)] = 2 * (1-c) / (am^3)      # ∂³foo/∂am²b
            want[1][(1, 1, 4)] = -2 * b / (am^3)         # ∂³foo/∂am²c
            want[1][(2, 2, 2)] = 2/(a^3)                 # ∂³foo/∂a³
            want[1][(1, 3, 4)] = 1/(am^2)                # ∂³foo / ∂a ∂b ∂c

            have = @inferred fun(Der{3}, V, p)

            @test length(have[1]) == 5
            @test length(have[2]) == 0
            for (k, v) in have[1]
                @test v ≈ want[1][k]
            end
        end
    end
end

@testset "issue #14" begin
    eqs = Expr[:(1+a-a)]
    ss_args = Tuple{Symbol,Int64}[(:a,0)]
    p_args = Symbol[:q]

    ff = Dolang.FunctionFactory(eqs, ss_args, p_args, funname=:f_s)
    # just make sure this runs
    Dolang.func_body(ff, Dolang.Der{2})
end

@testset "grouped version" begin

    m = [0.0, 0.0]
    s = [9.35498]
    x = [0.33, 0.233874]
    p = [0.99, 5.0, 1.0, 23.9579, 0.025, 0.33, 0.8, 0.0, 0.016]

    code = make_function(ff_grouped)
    Core.eval(@__MODULE__, code)

    # allocating
    want = [1.0123335492995267e-5, 4.255452989987418e-9]
    @test want ≈ @inferred anon(m, s, x, m, s, x, p)

    # mutating
    out = zeros(2)
    @inferred anon!(out, m, s, x, m, s, x, p)
    @test want ≈ out

    # allocating vectorized
    want2 = [want want]'
    @test want2 ≈ @inferred anon([m m]', s, x, m, s, x, p)

    # mutating vectorized
    out2 = zeros(2, 2)
    want2 = [want want]'
    @inferred anon!(out2, [m m]', s, x, m, s, x, p)
    @test want2 ≈ out2

    # alllocating first derivative
    want3 = ([11.1848 0.0; -6.53625 0.0],
            reshape([0.394547; -0.230568], (2, 1)),
            [34.9526 -13.2706; -13.2706 6.56871],
            [0.0 0.0; 6.5015 0.0],
            reshape([0.0; 0.233057], (2, 1)),
            [0.0 0.0; 13.2 -6.56871])
    @test begin
        out = @inferred anon(Der{1}, m, s, x, m, s, x, p)
        true
    end
    for i in 1:length(want3)
        @test isapprox(want3[i], out[i], atol=1e-4)
    end

    # mutating first derivative
    out3 = deepcopy(want3)
    map(_x -> fill!(_x, 0.0), out3)
    @test begin
        @inferred anon!(Der{1}, out3, m, s, x, m, s, x, p)
        true
    end
    for i in 1:length(want3)
        @test isapprox(want3[i], out3[i], atol=1e-4)
    end
end


end  # @testset "compiler"
