function extend_state_space!(h::Hank, qʰ_mat, qᵍ_mat, T_mat)

	Npn = length(h.pngrid)

	ϕa_ext = Array{Float64}(h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz, Npn)
	ϕb_ext = Array{Float64}(h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz, Npn)
	ϕc_ext = Array{Float64}(h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz, Npn)

	# all_knots = (h.ωgrid, 1:h.Nϵ, h.bgrid, h.μgrid, h.σgrid, h.wgrid, 1:h.Nζ, 1:h.Nz)
	# agg_knots = (h.bgrid, h.μgrid, h.σgrid, h.wgrid, 1:h.Nζ, 1:h.Nz)
	# itp_vf = interpolate(all_knots, h.vf, (Gridded(Linear()), NoInterp(), Gridded(Linear()), Gridded(Linear()),Gridded(Linear()),Gridded(Linear()), NoInterp(), NoInterp()))
	# itp_qᵍ  = interpolate(agg_knots, qᵍ_mat, (Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), NoInterp(), NoInterp()))

	# ωrange = linspace(h.ωgrid[1], h.ωgrid[end], h.Nω)
	# brange = linspace(h.bgrid[1], h.bgrid[end], h.Nb)
	# μrange = linspace(h.μgrid[1], h.μgrid[end], h.Nμ)
	# σrange = linspace(h.σgrid[1], h.σgrid[end], h.Nσ)
	# wrange = linspace(h.wgrid[1], h.wgrid[end], h.Nw)

	# unscaled_itp_vf = interpolate(h.vf, (BSpline(Quadratic(Line())), NoInterp(), BSpline(Linear()), BSpline(Linear()), BSpline(Linear()), BSpline(Linear()), NoInterp(), NoInterp()), OnGrid())
	# unscaled_itp_qᵍ  = interpolate(qᵍ_mat, (BSpline(Linear()), BSpline(Linear()), BSpline(Linear()), BSpline(Linear()), NoInterp(), NoInterp()), OnGrid())
	# itp_vf = Interpolations.scale(unscaled_itp_vf, ωrange, 1:h.Nϵ, brange, μrange, σrange, wrange, 1:h.Nζ, 1:h.Nz)
	# itp_qᵍ = Interpolations.scale(unscaled_itp_qᵍ, brange, μrange, σrange, wrange, 1:h.Nζ, 1:h.Nz)

	itp_vf, itp_qᵍ = make_itps(h, h.vf, qᵍ_mat)


	print_save("\nExtending the state space ($(Npn) iterations needed)")

	# @sync @parallel for jpn in 1:Npn
	for jpn in 1:Npn

		pnv = h.pngrid[jpn]
		
		N = size(h.Jgrid, 1)

		wage_pn, labor_pn, profits_pn = Array{Float64, 1}(N), Array{Float64, 1}(N), Array{Float64, 1}(N)
		for js in 1:N
			jw = h.Jgrid[js, 4]
			jζ = h.Jgrid[js, 5]
			jz = h.Jgrid[js, 6]

			wv = h.wgrid[jw]
			ζv = h.ζgrid[jζ]
			zv = h.zgrid[jz]

			jdef = (ζv != 1.0)

			labor_pn[js], wage_pn[js], profits_pn[js], _ = labor_market(h, jdef, zv, wv, pnv)
		end

		pC = price_index(h, pnv)
		pC_mat = ones(h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz) * pC

		T_mat = govt_bc(h, wage_pn.*labor_pn) - reshape(profits_pn, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)

		wL_mat  = reshape(wage_pn.*labor_pn, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz) * (1.0 - h.τ)

		# Re-solve for these values of wn and pn
		_, ϕa, ϕb, ϕc = opt_value(h, qʰ_mat, qᵍ_mat, wL_mat, T_mat, pC_mat, itp_qᵍ, itp_vf)
			
		ϕa_ext[:,:,:,:,:,:,:,:,jpn] = reshape(ϕa, h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)
		ϕb_ext[:,:,:,:,:,:,:,:,jpn] = reshape(ϕb, h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)
		ϕc_ext[:,:,:,:,:,:,:,:,jpn] = reshape(ϕc, h.Nω, h.Nϵ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)
	end

	h.ϕa_ext = ϕa_ext
	h.ϕb_ext = ϕb_ext
	h.ϕc_ext = ϕc_ext

	Void
end

transform_vars(m::Float64, cmin, cmax) = cmax - (cmax-cmin)/(1+exp(m))

function _unpack_origvars(x, xmin, xmax)
	y = zeros(x)
	for (jx, xv) in enumerate(x)
		y[jx] = transform_vars(xv, xmax[jx], xmin[jx])
	end
	return y
end

function labor_demand(h::Hank, w, tfp, pN; get_both::Bool = false)

	Ld_nontradables = (h.α_N * pN  / w).^(1.0/(1.0-h.α_N))
	Ld_tradables    = (h.α_T * tfp / w).^(1.0/(1.0-h.α_T))

	if get_both
		return Ld_nontradables, Ld_tradables
	else
		return Ld_nontradables + Ld_tradables
	end
end

function labor_market(h::Hank, jdef, zv, wv, pNv)
	""" Finds w and Lᵈ at the current state given a guess of pNv """
	TFP = ifelse(jdef, (1.0 - h.Δ) * exp(zv), exp(zv))
	w_constraint = h.γw * wv

	# Step 1: Assume w_t is at the constraint, find labor demand, and check whether the eq'm wage is above or below
	Ld_N, Ld_T = labor_demand(h, w_constraint, TFP, pNv; get_both=true)
	Ld = Ld_N + Ld_T

	# Step 2: If labor demand is lower than supply, find the wage above γw * wv that clears the labor mkt
	Ls = 1.0
	w_max = maximum(h.wgrid)
	if w_max < w_constraint
		print_save("\nSomething wrong with wages")
		w_max = w_constraint
	end

	w_new = w_constraint

	if Ld > Ls && !isapprox(Ld, Ls)
		res = Optim.optimize(
			w -> (labor_demand(h, w, TFP, pNv) - Ls)^2,
				w_constraint, w_max, GoldenSection()
			)
		w_new = res.minimizer
		minf = Ls - labor_demand(h, w_new, TFP, pNv)
		abs(minf) > 1e-6? print_save("\nWARNING: Labor exc supply = $(@sprintf("%0.3g",minf)) at (w, γw₀) = ($(@sprintf("%0.3g",w_new)), $(@sprintf("%0.3g",w_max)))"): Void
		Ld_N, Ld_T = labor_demand(h, w_new, TFP, pNv; get_both=true)
		Ld = Ld_N + Ld_T
	end

	output 	= pNv .* Ld_N.^h.α_N + TFP .* Ld_T.^h.α_T
	profits = output - w_new * (Ld_N + Ld_T)

	return Ld, w_new, profits, output
end


function mkt_clearing(h::Hank, itp_ϕc, G, Bpv, pNv, pNmin, pNmax, bv, μv, σv, wv, jζ, jz, jdefault; orig_vars::Bool = true, get_others::Bool = false)
	pN = pNv[1]
	if orig_vars == false
		pN = transform_vars(pN, pNmin, pNmax)
	end

	ζv, zv = h.ζgrid[jζ], h.zgrid[jz]

	Ld, w_new, profits, output = labor_market(h, jdefault, zv, wv, pN)

	# Step 3: Get the household's policies at these prices

	val_A, val_B, val_C, sum_prob = 0., 0., 0., 0.
	val_int_C = 0.
	for (jϵ, ϵv) in enumerate(h.ϵgrid)

		f(ω) = pdf(LogNormal(μv, σv), ω-h.ωmin) * h.λϵ[jϵ] * itp_ϕc[ω, jϵ, bv, μv, σv, wv, jζ, jz, pN]

		(val, err) = hquadrature(f, h.ωmin, h.ωmax,
									reltol=1e-8, abstol=0, maxevals=0)

		val_int_C += val
	end
	if sum_prob > 0
		val_int_C = val_C / sum_prob
	end

	# Step 4: Check market clearing for nontradables
	TFP = ifelse(jdefault, (1.0 - h.Δ) * exp(zv), exp(zv))
	Ld_N, _  = labor_demand(h, w_new, TFP, pN; get_both=true)
	supply_N = TFP * Ld_N^(h.α_N)

	demand = val_int_C
	demand_N_govt = G / pN

 	# Recover nontraded demand from total consumption
	pC = price_index(h, pN)
	demand_N = demand * h.ϖ * (pN/pC)^(-h.η) + demand_N_govt

	F = supply_N - demand_N

	if get_others
		return w_new, Ld, output
	else
		return F
	end
end

function find_prices(h::Hank, itp_ϕc, G, Bpv, pNg, pNmin, pNmax, bv, μv, σv, wv, jζ, jz, jdefault)

	function wrap_mktclear!(pN::Vector, fvec=similar(x))

		out = mkt_clearing(h, itp_ϕc, G, Bpv, pN, pNmin, pNmax, bv, μv, σv, wv, jζ, jz, jdefault; orig_vars = false)

		fvec[:] = out
	end
	
	res = fsolve(wrap_mktclear!, [pNg])
	if res.:converged == false
		res2 = fsolve(wrap_mktclear!, [pNg], method=:lmdif)

		if res2.:converged || sum(res2.:f.^2) < sum(res.:f.^2)
			res = res2
		end
	end

	minf = res.:f[1]

	pN = transform_vars(res.:x[1], pNmin, pNmax)

	w, Ld, output = mkt_clearing(h, itp_ϕc, G, Bpv, pN, pNmin, pNmax, bv, μv, σv, wv, jζ, jz, jdefault; get_others=true)

	results = [w; pN; Ld; output]

	if abs(minf) > 1e-4
		# print_save("\nNontradables exc supply = $(@sprintf("%0.4g",minf)) at pN = $(@sprintf("%0.4g",pN))")
	end

	return results, minf
end

function find_all_prices(h::Hank, itp_ϕc, B′_vec, G_vec)

	N = size(h.Jgrid, 1)

	results = SharedArray{Float64}(N, 4)
	minf	= SharedArray{Float64}(N, 1)

	pN_guess = h.pN

	@sync @parallel for js in 1:N
		Bpv = B′_vec[js]
		G = G_vec[js]
		pNg = pN_guess[js]

		jb = h.Jgrid[js, 1]
		jμ = h.Jgrid[js, 2]
		jσ = h.Jgrid[js, 3]
		jw = h.Jgrid[js, 4]
		jζ = h.Jgrid[js, 5]
		jz = h.Jgrid[js, 6]

		bv = h.bgrid[jb]
		μv = h.μgrid[jμ]
		σv = h.σgrid[jσ]
		wv = h.wgrid[jw]
		ζv = h.ζgrid[jζ]
		zv = h.zgrid[jz]

		jdefault = (ζv != 1.0)

		pNmin, pNmax = minimum(h.pngrid), maximum(h.pngrid)

		results[js, :], minf[js, :] = find_prices(h, itp_ϕc, G, Bpv, pNg, pNmin, pNmax, bv, μv, σv, wv, jζ, jz, jdefault)
	end
		
	
	return results, minf
end

function update_state_functions!(h::Hank, upd_η::Float64)
	all_knots = (h.ωgrid, 1:h.Nϵ, h.bgrid, h.μgrid, h.σgrid, h.wgrid, 1:h.Nζ, 1:h.Nz, h.pngrid)

	itp_ϕc  = interpolate(all_knots, h.ϕc_ext, (Gridded(Linear()), NoInterp(), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), NoInterp(), NoInterp(), Gridded(Linear())))

	results, minf = find_all_prices(h, itp_ϕc, h.issuance, h.spending)

	dist = Array{Float64,1}(3)
	dist[1] = sqrt.(sum( (results[:, 1] - h.wage).^2 )) / sqrt.(sum(h.wage.^2))
	dist[2] = sqrt.(sum( (results[:, 2] - h.pN).^2 ))   / sqrt.(sum(h.pN.^2))
	dist[3] = sqrt.(sum( (results[:, 3] - h.Ld).^2 ))   / sqrt.(sum(h.Ld.^2))

	h.wage 	 = upd_η * results[:, 1] + (1.0-upd_η) * h.wage
	h.pN 	 = upd_η * results[:, 2] + (1.0-upd_η) * h.pN
	h.Ld 	 = upd_η * results[:, 3] + (1.0-upd_η) * h.Ld
	h.output = upd_η * results[:, 4] + (1.0-upd_η) * h.output

	h.w′	 = h.wage

	mean_f = mean(minf)

	up_prop   = sum(minf .>  1e-4) / length(minf)
	down_prop = sum(minf .< -1e-4) / length(minf)
	return up_prop, down_prop, mean_f, dist
end

function update_grids_pw!(h::Hank, up_prop, down_prop)
	
	pN_down = minimum(h.pngrid)
	if up_prop > 0.05
		pN_down = pN_down * 0.95
	elseif up_prop == 0.
		pN_down = pN_down * 1.01
	end
	pN_up = maximum(h.pngrid)
	if down_prop > 0.05
		pN_up = pN_up * 1.05
	elseif down_prop == 0.
		pN_up = pN_up * 0.99
	end

	Ls = 1.0
	res = Optim.optimize(
			w -> (labor_demand(h, w, exp(h.zgrid[end]), pN_up) - Ls).^2,
			h.wgrid[1], h.wgrid[end] * 2.0, GoldenSection()
			)
	w_up = res.minimizer
	res = Optim.optimize(
			w -> (labor_demand(h, w, (1.0-h.Δ) * exp(h.zgrid[1]), pN_down) - Ls).^2,
			0.5 * h.wgrid[1], h.wgrid[end], GoldenSection()
			)
	w_down = res.minimizer

	h.pngrid = collect(linspace(pN_down, pN_up, length(h.pngrid)))
	new_wgrid = collect(linspace(w_down, w_up, h.Nw))
	
	return new_wgrid
end


function find_q(h::Hank, q, a, b, var_a, var_b, cov_ab, Bpv, wpv, thres, jzp, jdef, itp_qᵍ, reentry; get_μσ::Bool=false)

	zpv = h.zgrid[jzp]

	ζpv = 1
	haircut = 0.0
	if jdef && reentry==false
		ζpv = 2
		haircut = 0.0
	end
	if jdef == false && zpv <= thres
		ζpv = 2
		haircut = h.ℏ
	end
	
	R = (ζpv==1) * h.κ + (1.0 - haircut) .* ((1.0-h.ρ)*q)

	Eω   = a + R*b
	varω = var_a + R^2 * var_b + 2*R * cov_ab

	# print_save("\nEω, varω = $Eω, $varω")
	Eσ2 = 1.0 + varω / ( (Eω - h.ωmin)^2 )
	
	Eσ2 > 0 || print_save("\n1 + vω / (Eω-ωmin)² = $(Eσ2)")

	σ2 = log( Eσ2 )

	μpv = log(Eω - h.ωmin) - 0.5 * σ2
	σpv = sqrt(σ2)

	new_q = itp_qᵍ[(1.0 - haircut) .* Bpv, μpv, σpv, wpv, ζpv, jzp]

	if get_μσ
		return μpv, σpv
	else
		return new_q
	end
end


function compute_stats_logN(h::Hank, ζv, a, b, var_a, var_b, cov_ab, itp_qᵍ, Bpv, wpv, thres)

	jdef = (ζv != 1.0)

	μ, σ = Array{Float64, 2}(h.Nz, 2), Array{Float64, 2}(h.Nz, 2)
	qᵍ = Array{Float64,2}(h.Nz, 2)

	for (jzp, zpv) in enumerate(h.zgrid)
		reentry = true
		qmin, qmax = minimum(h.qᵍ), maximum(h.qᵍ)

		res = Optim.optimize(
			q -> (find_q(h, q, a, b, var_a, var_b, cov_ab, Bpv, wpv, thres, jzp, jdef, itp_qᵍ, reentry) - q)^2,
			qmin, qmax, Brent()
			)
		qᵍ[jzp, 1] = res.minimizer
		res.minimum > 1e-4? print_save("WARNING: Error in qᵍ = $(@sprintf("%0.3g",res.minimum))"): Void

		μ[jzp, 1], σ[jzp, 1] = find_q(h, qᵍ[jzp, 1], a, b, var_a, var_b, cov_ab, Bpv, wpv, thres, jzp, jdef, itp_qᵍ, reentry; get_μσ = true)

		if jdef
			reentry = false
			res = Optim.optimize(
				q -> (find_q(h, q, a, b, var_a, var_b, cov_ab, Bpv, wpv, thres, jzp, jdef, itp_qᵍ, reentry) - q)^2,
				qmin, qmax, GoldenSection()
				)
			qᵍ[jzp,2] = res.minimizer
			res.minimum > 1e-4? print_save("WARNING: Error in qᵍ = $(@sprintf("%0.3g",res.minimum))"): Void

			μ[jzp, 2], σ[jzp, 2] = find_q(h, qᵍ[jzp,2], a, b, var_a, var_b, cov_ab, Bpv, wpv, thres, jzp, jdef, itp_qᵍ, reentry; get_μσ = true)
		else
			μ[jzp, 2], σ[jzp, 2] = μ[jzp, 1], σ[jzp, 1]
			qᵍ[jzp, 2] = qᵍ[jzp, 1]
		end
	end

	return μ, σ, qᵍ
end

function new_expectations(h::Hank, itp_ϕa, itp_ϕb, itp_qᵍ, Bpv, wpv, thres, bv, μv, σv, wv, ζv, zv, jdef)
	
	val_a, val_b, val_a2, val_b2, val_ab, sum_prob = 0., 0., 0., 0., 0., 0.
	for (jϵ, ϵv) in enumerate(h.ϵgrid)
		for jω = 1:length(h.ωgrid_fine)-1
			ωv  = h.ωgrid_fine[jω]
			ω1v = h.ωgrid_fine[jω+1]
			ωmv = 0.5*(ωv+ω1v)

			prob = pdf(LogNormal(μv, σv), ωmv-h.ωmin) * h.λϵ[jϵ] * (ω1v - ωv)

			ϕa = itp_ϕa[ωmv, jϵ, bv, μv, σv, wv, ζv, zv]
			ϕb = itp_ϕb[ωmv, jϵ, bv, μv, σv, wv, ζv, zv]

			val_a  += prob * ϕa
			val_a2 += prob * ϕa^2
			val_b  += prob * ϕb
			val_b2 += prob * ϕb^2
			val_ab += prob * ϕa * ϕb
			
			sum_prob += prob
		end
	end

	a  = val_a  / sum_prob
	a2 = val_a2 / sum_prob
	b  = val_b  / sum_prob
	b2 = val_b2 / sum_prob
	ab = val_ab / sum_prob

	var_a  = a2 - a^2
	var_b  = b2 - b^2
	cov_ab = ab - a*b

	# print_save("\nVa, Vb, cov = $var_a, $var_b, $cov_ab")

	μ′, σ′, qᵍ = compute_stats_logN(h, ζv, a, b, var_a, var_b, cov_ab, itp_qᵍ, Bpv, wpv, thres)

	return μ′, σ′, qᵍ
end


function find_all_expectations(h::Hank, itp_ϕa, itp_ϕb, itp_qᵍ, B′_vec, w′_vec, thres_vec)
	N = size(h.Jgrid, 1)

	μ′ = SharedArray{Float64}(N, h.Nz, 2)
	σ′ = SharedArray{Float64}(N, h.Nz, 2)

	@sync @parallel for js in 1:N
		Bpv = B′_vec[js]
		wpv = w′_vec[js]
		thres = thres_vec[js]

		bv = h.bgrid[h.Jgrid[js, 1]]
		μv = h.μgrid[h.Jgrid[js, 2]]
		σv = h.σgrid[h.Jgrid[js, 3]]
		wv = h.wgrid[h.Jgrid[js, 4]]
		ζv = h.ζgrid[h.Jgrid[js, 5]]
		zv = h.zgrid[h.Jgrid[js, 6]]

		jζ = h.Jgrid[js, 5]
		jdefault = (jζ != 1.0)

		μ′[js, :, :], σ′[js, :, :], _ = new_expectations(h, itp_ϕa, itp_ϕb, itp_qᵍ, Bpv, wpv, thres, bv, μv, σv, wv, ζv, zv, jdefault)
	end
		
	
	return μ′, σ′
end

function update_expectations!(h::Hank, upd_η::Float64)
	""" 
	Computes mean and variance of tomorrow's distribution and deduces parameters for logN
	"""

	μ′_old = copy(h.μ′)
	σ′_old = copy(h.σ′)

	dist_exp = Array{Float64,1}(2)
	qᵍmt = reshape(h.qᵍ, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)

	all_knots = (h.ωgrid, 1:h.Nϵ, 1:h.Nb, 1:h.Nμ, 1:h.Nσ, 1:h.Nw, 1:h.Nζ, 1:h.Nz)
	agg_knots = (h.bgrid, h.μgrid, h.σgrid, h.wgrid, 1:h.Nζ, h.zgrid)

	itp_ϕa = interpolate(all_knots, h.ϕa, (Gridded(Linear()), NoInterp(), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), NoInterp(), Gridded(Linear())))
	itp_ϕb = interpolate(all_knots, h.ϕb, (Gridded(Linear()), NoInterp(), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), NoInterp(), Gridded(Linear())))
	itp_qᵍ = interpolate(agg_knots, qᵍmt, (Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), Gridded(Linear()), NoInterp(), Gridded(Linear())))

	μ′_new, σ′_new = find_all_expectations(h, itp_ϕa, itp_ϕb, itp_qᵍ, h.issuance, h.w′, h.def_thres)
	# μ′_new, σ′_new = h.μ′, h.σ′


	function new_grid(x′, xgrid)
		xmax = maximum(x′)
		xmin = minimum(x′)

		Nx = length(xgrid)

		# Expand grids if x′ goes beyond the bounds
		maximum(x′) > maximum(xgrid)? xmax = xmax + 0.5 * (maximum(x′) - xmax): Void
		minimum(x′) < minimum(xgrid)? xmin = xmin - 0.5 * (xmin - minimum(x′)): Void

		# Retract grids if x′ doesn't reach the bounds
		maximum(x′) < maximum(xgrid)? xmax = xmax - 0.1 * (xmax - maximum(x′)): Void
		minimum(x′) > minimum(xgrid)? xmin = xmin + 0.1 * (minimum(x′) - xmin): Void

		return collect(linspace(xmin, xmax, Nx))
	end

	μ′_new = max.(min.(μ′_new, maximum(h.μgrid)), minimum(h.μgrid))
	σ′_new = max.(min.(σ′_new, maximum(h.σgrid)), minimum(h.σgrid))

	dist_exp[1] = sqrt.(sum( (μ′_new - μ′_old).^2 )) / sqrt.(sum(μ′_old.^2))
	dist_exp[2] = sqrt.(sum( (σ′_new - σ′_old).^2 )) / sqrt.(sum(σ′_old.^2))	

	μ′_new = upd_η * μ′_new + (1.0 - upd_η) * μ′_old
	σ′_new = upd_η * σ′_new + (1.0 - upd_η) * σ′_old

	h.μ′ = μ′_new
	h.σ′ = σ′_new

	return dist_exp
end

function update_grids!(h::Hank; new_μgrid::Vector=[], new_σgrid::Vector=[], new_wgrid::Vector=[])

	if new_μgrid==[]
		new_μgrid = h.μgrid
	end
	if new_σgrid==[]
		new_σgrid = h.σgrid
	end
	if new_wgrid==[]
		new_wgrid = h.wgrid
	end

	function reinterp(h::Hank, y; agg::Bool=false)
		knots = (h.ωgrid, h.ϵgrid, h.bgrid, h.μgrid, h.σgrid, h.wgrid, h.ζgrid, h.zgrid)
		if agg
			knots = (h.bgrid, h.μgrid, h.σgrid, h.wgrid, h.ζgrid, h.zgrid)
			y = reshape(y, h.Nb, h.Nμ, h.Nσ, h.Nw, h.Nζ, h.Nz)
		end

		itp_obj_y = interpolate(knots, y, Gridded(Linear()))
		itp_y = extrapolate(itp_obj_y, Linear())

		if agg
			y_new = itp_y[h.bgrid, new_μgrid, new_σgrid, new_wgrid, h.ζgrid, h.zgrid]
			return reshape(y_new, size(h.Jgrid,1))
		else
			y_new = itp_y[h.ωgrid, h.ϵgrid, h.bgrid, new_μgrid, new_σgrid, new_wgrid, h.ζgrid, h.zgrid]
			return y_new
		end
	end

	h.ϕa = reinterp(h, h.ϕa, agg=false)
	h.ϕb = reinterp(h, h.ϕb, agg=false)
	h.ϕc = reinterp(h, h.ϕc, agg=false)
	h.vf = reinterp(h, h.vf, agg=false)

	h.Ld 		= reinterp(h, h.Ld, agg=true)
	h.wage 		= reinterp(h, h.wage, agg=true)
	h.repay 	= reinterp(h, h.repay, agg=true)
	h.issuance 	= reinterp(h, h.issuance, agg=true)
	h.spending 	= reinterp(h, h.spending, agg=true)
	h.pN 		= reinterp(h, h.pN, agg=true)
	h.w′ 		= reinterp(h, h.w′, agg=true)

	for jzp in 1:h.Nz
		for jreent in 1:2
			h.μ′[:,jzp,jreent] = reinterp(h, h.μ′[:,jzp,jreent], agg=true)
			h.σ′[:,jzp,jreent] = reinterp(h, h.σ′[:,jzp,jreent], agg=true)
		end
	end

	h.μgrid = new_μgrid
	h.σgrid = new_σgrid
	h.wgrid = new_wgrid

	h.μ′ = max.(min.(h.μ′, maximum(h.μgrid)), minimum(h.μgrid))
	h.σ′ = max.(min.(h.σ′, maximum(h.σgrid)), minimum(h.σgrid))
	h.w′ = max.(min.(h.w′, maximum(h.wgrid)), minimum(h.wgrid))

	Void
end