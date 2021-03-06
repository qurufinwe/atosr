function get_abc(RHS, ωmin, qʰv, qᵍv, pCv, sp, θp)
	""" Recovers private and public debt purchases and consumption from savings decisions """
	ap = ωmin .+ θp * (sp .- ωmin)
	bp = (1 .- θp) * (sp .- ωmin) * qʰv/qᵍv
	C  = (RHS .- qʰv*sp) / pCv

	return Dict(:a=>ap, :b=>bp, :c=>C)
end

function value(sd::SOEdef, sp, itp_wf_s, jϵ, RHS, qʰv, qᵍv, pCv)
	ψ, β = [sd.pars[key] for key in [:ψ, :β]]
	ct = get_abc(RHS, sd.pars[:ωmin], qʰv, qᵍv, pCv, sp, 0)[:c]

	wt = itp_wf_s[jϵ](sp)

	if ψ != 1
		ct > 1e-10 ? ut = ct^((ψ-1.0)/ψ) : ut = 1e-10

		vt = ((1-β) * ct^((ψ-1)/ψ) + β * wt^((ψ-1)/ψ))^(ψ/(ψ-1))
	else
		ct > 1e-10 ? ut = ct^(1-β) : ut = 1e-10
		vt = ut * wt^β # This is the same as saying that vt = exp( (1.0-β)*log(c) + h.β * log(Tv) )
	end
	return vt
end

function EZ_G(v, γ)
	if γ != 1
		return v^(1-γ)
	else
		return log(v)
	end
end

function EZ_T(Ev, γ)
	if γ != 1.0
		return Ev^(1.0/(1.0-γ))
	else
		return exp(Ev)
	end
end

function walue(sd::SOEdef, θp, itp_vf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef)
	pars, gr = sd.pars, sd.gr
	abc = get_abc(RHS, sd.pars[:ωmin], qʰv, qᵍv, pCv, ωv, θp)
	ap, bp = abc[:a], abc[:b]

	ωmax = maximum(sd.gr[:ω]) - 1e-6

	Ev, sum_prob = 0.0, 0.0
	out_bounds = 0
	if jdef
		for (jξp, ξpv) in enumerate(gr[:ξ])
			for (jzp, zpv) in enumerate(gr[:z])
				agg_prob = sd.prob[:z][jz, jzp] * sd.prob[:ξ][jξ, jξp]
				if agg_prob > 1e-8
					for (jϵp, ϵpv) in enumerate(gr[:ϵ])
						prob = agg_prob * sd.prob[:ϵ][jϵ, jϵp]

						# Reentry
						jζp = 2
						Rb = pars[:κ] + (1-pars[:ρ]) * qᵍp[jξp, jzp, jζp]
						ωpv = ap + bp * Rb
						if ωpv < pars[:ωmin]
							out_bounds += 1
							Ev += prob * pars[:θ] * 1e-32
						else
							# ωpv = min(ωmax, ωpv)
							v = itp_vf_s[jξp, jzp, jζp](ωpv, ϵpv)
							Ev += EZ_G(v, pars[:γ]) * prob * pars[:θ]
						end

						# Continue in default
						jζp = 1
						Rb = qᵍp[jξp, jzp, jζp]
						ωpv = ap + bp * Rb
						if ωpv < pars[:ωmin]
							out_bounds += 1
							Ev += prob * (1-pars[:θ]) * 1e-32
						else
							# ωpv = min(ωmax, ωpv)
							v = itp_vf_s[jξp, jzp, jζp](ωpv, ϵpv)
							Ev += EZ_G(v, pars[:γ]) * prob * (1-pars[:θ])
						end
						sum_prob += prob
					end
				end
			end
		end
	else
		for (jξp, ξpv) in enumerate(gr[:ξ])
			for (jzp, zpv) in enumerate(gr[:z])
				agg_prob = sd.prob[:z][jz, jzp] * sd.prob[:ξ][jξ, jξp]
				if agg_prob > 1e-8
					for (jϵp, ϵpv) in enumerate(gr[:ϵ])
						prob = agg_prob * sd.prob[:ϵ][jϵ, jϵp]

						# Repayment
						jζp = 2
						Rb = pars[:κ] + (1-pars[:ρ]) * qᵍp[jξp, jzp, jζp]
						ωpv = ap + bp * Rb
						if ωpv < pars[:ωmin]
							out_bounds += 1
							Ev += prob * exp_rep[jξp, jzp] * 1e-32
						else
							# ωpv = min(ωmax, ωpv)
							v = itp_vf_s[jξp, jzp, jζp](ωpv, ϵpv)
							Ev += EZ_G(v, pars[:γ]) * prob * exp_rep[jξp, jzp]
						end

						# Default
						jζp = 1
						Rb = (1-pars[:ℏ]) * qᵍp[jξp, jzp, jζp]
						ωpv = ap + bp * Rb
						if ωpv < pars[:ωmin]
							out_bounds += 1
							Ev += prob * (1-exp_rep[jξp, jzp]) * 1e-32
						else
							# ωpv = min(ωmax, ωpv)
							v = itp_vf_s[jξp, jzp, jζp](ωpv, ϵpv)
							Ev += EZ_G(v, pars[:γ]) * prob * (1. - exp_rep[jξp, jzp])
						end
						sum_prob += prob
					end
				end
			end
		end
	end

	Ev = Ev / sum_prob

	Ev = Ev / (1+out_bounds)
	if Ev < -1
		throw(error("Something wrong in the choice of ωpv"))
	elseif Ev < 0
		Ev = 1e-6
	end
	wt = EZ_T(Ev, pars[:γ])

	return wt
end

function solve_optvalue(sd::SOEdef, guess, itp_vf_s, itp_wf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef, ωmax; autodiff::Bool=false)
	smax = min(RHS/qʰv, ωmax)
	smin = sd.pars[:ωmin]
	s_space = smax - smin
	if s_space > 2e-6
		smax -= 1e-6
		smin += 1e-6
	else
	end

	θmin, θmax = 0.0, 1.0

	warnc = 0.0

	ϕp = Dict{Symbol, Float64}(key => val for (key,val) in guess)
	vp = Dict{Symbol, Float64}(key => 0.0 for key in [:v, :w])

	# First resolve the v value function
	sguess = max(min(guess[:s], smax - 0.1*s_space))
	obj_v(x) = -value(sd, first(x), itp_wf_s, jϵ, RHS, qʰv, qᵍv, pCv)
	if s_space > 2e-6
		if autodiff
			od = OnceDifferentiable(obj_v, [sguess]; autodiff = :forward)

			res = Optim.optimize(od, [smin], [smax], [sguess], Fminbox(BFGS()))
			ϕp[:s] = first(res.minimizer)
			vp[:v] = first(-od(res.minimizer))
		else
			# res = Optim.optimize(obj_v, [smin], [smax], [sguess], Fminbox(BFGS()))
			res = Optim.optimize(obj_v, smin, smax, GoldenSection())
			ϕp[:s] = first(res.minimizer)
			vp[:v] = first(-obj_v(res.minimizer))
		end
	else
		ϕp[:s] = sd.pars[:ωmin]
		vp[:v] = 1e-10
		warnc = 1.0
	end

	if sd.opt[:nob]
		ϕp[:θ] = 1.0
		vp[:w] = walue(sd, 1, itp_vf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef) 
	else
		# Then resolve the w value function
		θguess = max(min(guess[:θ], θmax-1e-6), θmin+1e-6)
		θguess = 0.5
		obj_w(x) = -walue(sd, first(x), itp_vf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef)
		if autodiff
			od = OnceDifferentiable(obj_w, [θguess]; autodiff = :forward)

			res = Optim.optimize(od, [θmin], [θmax], [θguess], Fminbox(BFGS()))
			ϕp[:θ] = first(res.minimizer)
			vp[:w] = first(-od(res.minimizer))
		else
			res = Optim.optimize(obj_w, θmin, θmax, GoldenSection())
			ϕp[:θ] = first(res.minimizer)
			vp[:w] = first(-obj_w(res.minimizer))
		end
	end

	others = get_abc(RHS, sd.pars[:ωmin], qʰv, qᵍv, pCv, ϕp[:s], ϕp[:θ])
	for (key, val) in others
		ϕp[key] = val
	end

	if ϕp[:c] <= 0 || isnan(ϕp[:c])
		ϕp[:a] = sd.pars[:ωmin]
		ϕp[:b] = 0
		ϕp[:c] = 1e-8
		ϕp[:s] = sd.pars[:ωmin]
		ϕp[:θ] = 0.95
		vp[:v] = 1e-10
		warnc = 1.0
	end

	return ϕp, vp, warnc
end

function eval_value(sd::SOEdef, guess, itp_vf_s, itp_wf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef)

	sguess = min(sd.pars[:ωmax],max(sd.pars[:ωmin], guess[:s]))

	vt = value(sd, sguess, itp_wf_s, jϵ, RHS, qʰv, qᵍv, pCv)
	wt = walue(sd, guess[:θ], itp_vf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef)

	return Dict(:v => vt, :w => wt)
end

function opt_value!(v, ϕ, warnc0, sd::SOEdef, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat, itp_qᵍ, itp_vf, itp_wf; resolve::Bool = true, verbose::Bool=true, autodiff::Bool=false)

	adjustment = sum(ergodic_ϵ(sd).*exp.(sd.gr[:ϵ]))
	ωmax = maximum(sd.gr[:ω])

	pars, gr, eq, LoM = sd.pars, sd.gr, sd.eq, sd.LoM;
	Jgrid = agg_grid(sd);
	Threads.@threads for js in 1:size(Jgrid,1)
	# for js in 1:size(Jgrid,1)
		jb = Jgrid[js, 1]
		jμ = Jgrid[js, 2]
		jσ = Jgrid[js, 3]
		jξ = Jgrid[js, 4]
		jζ = Jgrid[js, 5]
		jz = Jgrid[js, 6]

		# jdef = (gr[:ζ][jζ] .== 0)
		jdef = (jζ == 1)

		qʰv = qʰ_mat[jb, jμ, jσ, jξ, jζ, jz]
		qᵍv = qᵍ_mat[jb, jμ, jσ, jξ, jζ, jz]
		wL  = wL_mat[jb, jμ, jσ, jξ, jζ, jz]
		Tv  = T_mat[jb, jμ, jσ, jξ, jζ, jz]
		pCv = pC_mat[jb, jμ, jσ, jξ, jζ, jz]
		profits = Π_mat[jb, jμ, jσ, jξ, jζ, jz]

		bpv = eq[:issuance][js]
		μpv = LoM[:μ][js,:,:]
		σpv = LoM[:σ][js,:,:]

		rep_mat = reshape_long_shocks(sd, sd.gov[:repay]);
		exp_rep = rep_mat[jb, jμ, jσ, jξ, jζ, jz, :, :]

		if verbose
			minimum(minimum(μpv)) < minimum(gr[:μ]) || maximum(maximum(μpv)) > maximum(gr[:μ]) ? print_save("\nμ out of bounds at $([jb,jμ,jσ,jξ,jζ,jz])") : nothing
			minimum(minimum(σpv)) < minimum(gr[:σ]) || maximum(maximum(σpv)) > maximum(gr[:σ]) ? print_save("\nσ out of bounds at $([jb,jμ,jσ,jξ,jζ,jz])") : nothing
			bpv - minimum(gr[:b]) < -1e-4 || bpv - maximum(gr[:b]) > 1e-4 ? print_save("\nb = $(round(bpv,6)) out of bounds at $([jb,jμ,jσ,jξ,jζ,jz])") : nothing
		end

		""" DECIDE IF WE ARE KEEPING THE PREINTERPOLATION """
		qᵍp = Array{Float64}(undef, N(sd,:ξ), N(sd,:z), 2)
		itp_vf_s = Arr_ext_vf{3,2}(undef, N(sd,:ξ), N(sd,:z), 2)
		for (jξp, ξpv) in enumerate(gr[:ξ])
			for (jzp, zpv) in enumerate(gr[:z])
				agg_prob = sd.prob[:z][jz, jzp] * sd.prob[:ξ][jξ, jξp]
				if agg_prob > 1e-8
					qᵍp[jξp, jzp, 2] = itp_qᵍ(bpv, μpv[jξp, jzp][2], σpv[jξp, jzp][2], ξpv, gr[:ζ][2], zpv)
					if jdef
						qᵍp[jξp, jzp, 1] = itp_qᵍ(bpv, μpv[jξp, jzp][1], σpv[jξp, jzp][1], ξpv, gr[:ζ][1], zpv)
					else
						qᵍp[jξp, jzp, 1] = itp_qᵍ((1.0 - pars[:ℏ])*bpv, μpv[jξp, jzp][1], σpv[jξp, jzp][1], ξpv, gr[:ζ][1], zpv)
					end
					vf_mat = Array{Float64}(undef, N(sd,:ω), N(sd,:ϵ), 2)
					for (jϵp, ϵpv) in enumerate(gr[:ϵ])
						for (jωp, ωpv) in enumerate(gr[:ω])
							vf_mat[jωp, jϵp, 2] = itp_vf(ωpv, ϵpv, bpv, μpv[jξp, jzp][2], σpv[jξp, jzp][2], ξpv, gr[:ζ][2], zpv)
							if jdef
								vf_mat[jωp, jϵp, 1] = itp_vf(ωpv, ϵpv, bpv, μpv[jξp, jzp][1], σpv[jξp, jzp][1], ξpv, gr[:ζ][1], zpv)
							else
								vf_mat[jωp, jϵp, 1] = itp_vf(ωpv, ϵpv, (1.0-pars[:ℏ])*bpv, μpv[jξp, jzp][1], σpv[jξp, jzp][1], ξpv, gr[:ζ][1], zpv)
							end
						end

					end
					knots = (gr[:ω], gr[:ϵ])
					for jj in 1:2
						itp_vf_s[jξp, jzp, jj] = extrapolate(interpolate(knots, vf_mat[:,:,jj], Gridded(Linear())), Interpolations.Line())
					end
				end
			end
		end
		itp_wf_s = Arr_ext_vf{1,1}(undef, N(sd,:ϵ))
		knots = (gr[:ω],)
		for (jϵ, ϵv) in enumerate(gr[:ϵ])
			wf = sd.v[:w][:,jϵ,jb,jμ,jσ,jξ,jζ,jz]
			itp_wf_s[jϵ] = extrapolate(interpolate(knots, wf, Gridded(Linear())), Interpolations.Line())
		end


		for (jϵ, ϵv) in enumerate(sd.gr[:ϵ]), (jω, ωv) in enumerate(sd.gr[:ω])
			RHS = ωv + (wL + profits) * exp(ϵv) / adjustment - Tv

			ϕp = Dict(sym => 0.0 for sym in keys(sd.ϕ))

			guess = Dict(sym => sd.ϕ[sym][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz] for sym in keys(sd.ϕ))
			if resolve
				ϕmax, fmax, warnc_0 = solve_optvalue(sd, guess, itp_vf_s, itp_wf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef, ωmax, autodiff=autodiff)
				warnc0[jb, jμ, jσ, jξ, jζ, jz] = warnc_0
			else
				ϕmax = guess
				fmax = eval_value(sd, guess, itp_vf_s, itp_wf_s, ωv, jϵ, jξ, jz, exp_rep, RHS, qʰv, qᵍv, qᵍp, profits, pCv, jdef)
			end

			for (key, val) in ϕmax
				ϕ[key][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz] = val
			end
			for (key, val) in fmax
				v[key][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz] = val
			end
		end
	end

	# return v, ϕ, warnc0
end

function update_policy!(ϕ, sd::SOEdef, itp_θ, qʰ_mat, qᵍ_mat)
	Jgrid = agg_grid(sd)

	for js in 1:size(Jgrid, 1)
		jb, jμ, jσ, jξ, jζ, jz = Jgrid[js, :]

		bt = sd.gr[:b][jb]
		μt = sd.gr[:μ][jμ]
		σt = sd.gr[:σ][jσ]
		ξt = sd.gr[:ξ][jξ]
		ζt = sd.gr[:ζ][jζ]
		zt = sd.gr[:z][jz]

		qʰv = qʰ_mat[js]
		qᵍv = qᵍ_mat[js]

		for (jϵ, ϵv) in enumerate(sd.gr[:ϵ]), (jω, ωv) in enumerate(sd.gr[:ω])
			sv = min(sd.pars[:ωmax], max(sd.pars[:ωmin], sd.ϕ[:s][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz]))
			θv = min(max(0.0, itp_θ(sv, ϵv, bt, μt, σt, ξt, ζt, zt)), 1.0)

			""" RHS, pCv irrelevant because I only want :a and :b """
			others = get_abc(1.0, sd.pars[:ωmin], qʰv, qᵍv, 1.0, sv, θv)

			ϕ[:a][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz] = others[:a]
			ϕ[:b][jω, jϵ, jb, jμ, jσ, jξ, jζ, jz] = others[:b]
		end
	end
	nothing
end

function bellman_iteration!(v, ϕ, warnc0, sd::SOEdef, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat; resolve::Bool=true, verbose::Bool=true, autodiff::Bool=false)
	# Interpolate the value function
	itp_vf = make_itp(sd, sd.v[:v]; agg=false);
	itp_wf = make_itp(sd, sd.v[:w]; agg=false);
	itp_qᵍ = make_itp(sd, sd.eq[:qᵍ]; agg=true);

	# Compute values
	opt_value!(v, ϕ, warnc0, sd, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat, itp_qᵍ, itp_vf, itp_wf, resolve = resolve, verbose = verbose, autodiff=autodiff)

	# Let know if anything is wrong
	for key in keys(v)
		if sum(isnan.(v[key])) > 0
			print_save("$(sum(isnan.(v[key]))) NaNs found in v[$(key)]")
		end
	end
	for key in keys(ϕ)
		if sum(isnan.(ϕ[key])) > 0
			print_save("$(sum(isnan.(ϕ[key]))) NaNs found in ϕ$(key)")
		end
	end

	itp_θ  = make_itp(sd, ϕ[:θ]; agg=false);

	# Store results in the type
	# sd.v = vf
	# sd.ϕ = ϕ

	# Store results for policy in :a and :b
	update_policy!(ϕ, sd, itp_θ, qʰ_mat, qᵍ_mat)

	# return warnc0, vf, ϕ
	nothing
end


function vfi!(sd::SOEdef{Ktot,Kshocks}; tol::Float64=5e-3, verbose::Bool=true, maxiter::Int64=200) where {Ktot,Kshocks}

	!verbose || print_save("\nSolving household problem: ")
	time_init = time()
	iter = 0
	dist = 1+tol

	upd_ηϕ = 0.75

	v = Dict{Symbol, Array{Float64,Ktot}}(key=>similar(val) for (key, val) in sd.v)
	ϕ = Dict{Symbol, Array{Float64,Ktot}}(key=>similar(val) for (key, val) in sd.ϕ)
	warnc0 = zeros(N(sd,:b), N(sd,:μ), N(sd,:σ), N(sd,:ξ), N(sd,:ζ), N(sd,:z))

	t_old = time()
	while dist > tol && iter < maxiter
		iter += 1
		qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat = _unpackstatefs(sd);

		if iter > 5
			for jj in 1:5
				bellman_iteration!(v, ϕ, warnc0, sd, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat; resolve=false)
				for (key, val) in v
					sd.v[key] = val
				end
			end
		end
		
		bellman_iteration!(v, ϕ, warnc0, sd, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, Π_mat; resolve=true, autodiff=false)


		dist_v = maximum([ norm( v[key] - sd.v[key] ) / norm(sd.v[key]) for key in keys(sd.v)])
		norm_v = Dict(key => norm(sd.v[key]) for key in keys(sd.v))
		dist_ϕ = maximum([norm( ϕ[key] - sd.ϕ[key] ) / (1+norm(sd.ϕ[key])) for key in [:s,:θ]])
		dist = max(dist_v, 0.1*dist_ϕ)
		# dist = 1 * dist_v

		for (key, val) in ϕ
			sd.ϕ[key] = sd.ϕ[key] + upd_ηϕ * (val - sd.ϕ[key])
		end
		for (key, val) in v
			sd.v[key] = val
		end

		if iter % 20 == 0 || (verbose && dist < tol)
			t_new = time()
			print("\nd(v, v′) = $(@sprintf("%0.3g",dist)) at ‖v,w‖ = ($(@sprintf("%0.3g",norm_v[:v])), $(@sprintf("%0.3g",norm_v[:w]))) after $(time_print(t_new-t_old)) and $iter iterations ")
			print(Dates.format(now(), "HH:MM"))
		end
	end
	return warnc0, dist
end