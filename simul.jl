include("type_def.jl")
	
function iter_simul!(h::Hank, p::Path, t, jz_series, itp_ϕa, itp_ϕb, itp_ϕc, itp_B′, itp_G, itp_pN, itp_qᵍ, itp_Zthres, λt, Qϵ; phase::String="")
	# Enter with a state B, μ, σ, w0, ζ, z.
	# h.zgrid[jz] must equal get(p, t, :z)
	# B, ζ, and z are decided at the end of the last period
	jz = jz_series[t]

	Bt = get(p, t, :B)
	μt = get(p, t, :μ)
	σt = get(p, t, :σ)
	w0 = get(p, t, :w)
	ζt = Int(get(p, t, :ζ))
	zt = get(p, t, :z)

	zt == h.zgrid[jz] || print_save("something wrong with the simulator", remote=remote)
	abs(zt - h.zgrid[jz]) < 1e-8 || throw(error("something wrong with the simulator"))

	print_save("\n$([Bt, μt, σt, w0, ζt, zt])", remote=remote)

	Bprime 	= itp_B′[Bt, μt, σt, w0, ζt, jz]
	G 		= itp_G[Bt, μt, σt, w0, ζt, jz]
	pNg 	= itp_pN[Bt, μt, σt, w0, ζt, jz]
	thres 	= itp_Zthres[Bt, μt, σt, w0, ζt, jz]

	# Find pN at the current state. Deduce w, L, Π, T.
	pNmin, pNmax = minimum(h.pngrid), maximum(h.pngrid)
	jdef = (ζt != 1)
	results, _ = find_prices(h, itp_ϕc, G, Bprime, pNg, pNmin, pNmax, Bt, μt, σt, w0, ζt, jz, jdef)

	wt, pN, Ld, output = results
	print_save("\npN = $pN, pN^e = $(pNg), σ = $(σt) at t = $t", remote=remote)

	def_prob = 0.
	if ζt == 1
		for (jzp, zvp) in enumerate(h.zgrid)
			if zvp <= thres
				def_prob += h.Pz[jz, jzp]
			end
		end
	end

	fill_path!(p,t, Dict(:P => pN, :Pe => pNg, :Y => output, :L => Ld, :π => def_prob))

	# Integrate the household's policy functions to get μ′, σ′
	ϕa = zeros(h.Nω_fine*h.Nϵ)
	ϕb = zeros(h.Nω_fine*h.Nϵ)
	js = 0
	for (jϵ, ϵv) in enumerate(h.ϵgrid)
		for (jω, ωv) in enumerate(h.ωgrid_fine)
			js += 1
			ϕa[js] = itp_ϕa[ωv, jϵ, Bt, μt, σt, w0, ζt, jz]
			ϕb[js] = itp_ϕb[ωv, jϵ, Bt, μt, σt, w0, ζt, jz]
		end
	end

	a  = dot(λt, ϕa)
	a2 = dot(λt, ϕa.^2)
	b  = dot(λt, ϕb)
	b2 = dot(λt, ϕb.^2)
	ab = dot(λt, ϕa.*ϕb)

	var_a  = a2 - a^2
	var_b  = b2 - b^2
	cov_ab = ab - a*b

	prop_domestic = b/Bprime

	# print_save("\nvar_a, var_b, cov_ab = $([var_a, var_b, cov_ab]), remote=remote")

	μ′, σ′, q′ = compute_stats_logN(h, ζt, a, b, var_a, var_b, cov_ab, itp_qᵍ, Bprime, wt, thres)
	# μ′, σ′, q′ = new_expectations(h, itp_ϕa, itp_ϕb, itp_qᵍ, Bprime, wt, thres, Bt, μt, σt, w0, ζt, zt, jdef) # This would assume that λₜ is lognormal
	# print_save("\n$(q′)", remote=remote)

	# Draw z and the reentry shock for tomorrow, deduce ζ and correct B, μ, and σ as needed, and update the distribution
	probs = cumsum(h.Pz[jz,:])
	jzp = findfirst(probs .> rand())

	if phase == "no_def"
		jzp = max(jzp, 2)
	elseif phase == "danger"
		jzp = 2
	end

	zprime = h.zgrid[jzp]

	μprime = μ′[jzp, 1]
	σprime = σ′[jzp, 1]
	qprime = q′[jzp, 1]
	if jdef
		prob_reentry = h.θ
		reentry = (rand() <= prob_reentry)
		if reentry
			ζprime = 1.0
			R = h.κ + (1.0-h.ρ) * qprime
		else
			ζprime = 2.0
			μprime = μ′[jzp, 2]
			σprime = σ′[jzp, 2]
			qprime = q′[jzp, 2]
			R = h.κ + (1.0-h.ρ) * qprime
		end
	else
		if zprime <= thres
			ζprime = 2.0
			Bprime = (1.0 - h.ℏ) * Bprime
			R = (1.0-h.ℏ)*(1.0-h.ρ) * qprime
		else
			ζprime = 1.0
			R = h.κ + (1.0-h.ρ) * qprime
		end
	end

	savings = ϕa + R*ϕb
	savings = max.(min.(savings, h.ωmax), h.ωmin)

	basis = Basis(LinParams(h.ωgrid_fine, 0))
	Qω = BasisMatrix(basis, Expanded(), savings, 0).vals[1]
	Q = row_kron(Qϵ, Qω)

	λprime = Q' * λt

	# Fill the path for next period
	if t < length(jz_series)
		jz_series[t+1] = jzp
		fill_path!(p,t+1, Dict(:B => Bprime, :μ => μprime, :σ => σprime, :w => wt, :ζ => ζprime, :z => zprime, :ψ => prop_domestic, :A => a, :Bh => b, :Bf => Bprime-b))
	end

	return λprime
end

function simul(h::Hank; simul_length::Int64=1, burn_in::Int64=0, only_def_end::Bool=false)

	srand(3)

	# Setup
	T = burn_in + simul_length
	p = Path(T = T)

	jz = 4

	B0, μ0, σ0, w0, ζ0, z0 = mean(h.bgrid), mean(h.μgrid), mean(h.σgrid), mean(h.wgrid), h.ζgrid[1], h.zgrid[jz]
	fill_path!(p,1, Dict(:B => B0, :μ => μ0, :σ => σ0, :w => w0, :ζ => ζ0, :z => z0))

	itp_ϕa = make_itp(h, h.ϕa; agg=false)
	itp_ϕb = make_itp(h, h.ϕb; agg=false)
	itp_ϕc = make_itp(h, h.ϕc_ext; agg=false)

	itp_B′		= make_itp(h, h.issuance; agg=true)
	itp_G		= make_itp(h, h.spending; agg=true)
	itp_pN		= make_itp(h, h.pN; agg=true)
	itp_qᵍ 		= make_itp(h, h.qᵍ; agg=true)
	itp_Zthres	= make_itp(h, h.def_thres; agg=true)

	jz_series = Vector{Int64}(T)
	jz_series[1] = jz

	# Initialize objects for iterating the distribution
	# λ = ones(h.Nω_fine*h.Nϵ) / (h.Nω_fine*h.Nϵ)
	λ = zeros(h.Nω_fine*h.Nϵ)
	js = 0
	for (jϵ, ϵv) in enumerate(h.ϵgrid)
		for jω = 1:length(h.ωgrid_fine)-1
			js += 1
			ωv  = h.ωgrid_fine[jω]
			ω1v = h.ωgrid_fine[jω+1]
			ωmv = 0.5*(ωv+ω1v)

			λ[js] = pdf(LogNormal(μ0, σ0), ωmv-h.ωmin) * h.λϵ[jϵ] * (ω1v - ωv)
		end
	end
	λ = λ / sum(λ)
	Qϵ = kron(h.Pϵ, ones(h.Nω_fine,1))

	# Simulate
	for t in 1:T
		# Advance one step
		phase = ""
		if only_def_end
			start_def = floor(Int, burn_in + 3/4 * simul_length)
			if t - burn_in < start_def
				phase = "no_def"
				if t - burn_in > start_def - 4*3.5
					phase = "danger"
				end
			end
		end

		λ = iter_simul!(h, p, t, jz_series, itp_ϕa, itp_ϕb, itp_ϕc, itp_B′, itp_G, itp_pN, itp_qᵍ, itp_Zthres, λ, Qϵ; phase = phase)
		# print_save("\nt = $t", remote=remote)
	end

	# Compute regs
	ols = simul_regs(p)

	# Keep only after the burn_in period
	p_full = p
	trim_path!(p, burn_in)
	jz_series = jz_series[burn_in+1:end]

	# Return stuff
	return p, p_full, jz_series, ols
end

using DataFrames, GLM
function simul_regs(path::Path)
	T = size(path.data, 1)

	B_vec = series(path,:B)
	μ_vec = series(path,:μ)
	σ_vec = series(path,:σ)
	w_vec = series(path,:w)
	ζ_vec = series(path,:ζ)-1
	z_vec = exp.(series(path,:z))
	Y_vec = series(path,:Y)
	π_vec = series(path,:π)

	print("\nT = $T")

	data = DataFrame(Y = log.(Y_vec), lz = log.(z_vec), w = log.(w_vec), μ = log.(μ_vec), σ = log.(σ_vec), B = log.(B_vec), π = π_vec)

	OLS = glm(@formula(Y ~ lz + w + μ + σ + B + π), data, Normal(), IdentityLink())

	OLS
end