function make_guess(nodef, noΔ, rep_agent, r_loc, tax, RRA, τ, ρz, σz, ρξ, σξ, wbar, run_number)

	print_save("\nRun with r_loc, RRA, τ, wbar, ρz, σz, tax, ρξ, σξ = $(round(r_loc,digits=3)), $(round(RRA,digits=3)), $(round(τ,digits=3)), $(round(wbar,digits=3)), $(round(ρz,digits=3)), $(round(σz,digits=3)), $(round(tax,digits=3)), $(round(ρξ,digits=3)), $(round(σξ,digits=3))")
	sd = SOEdef(; β=(1.0/(1.0+r_loc))^0.25, tax = tax, RRA=RRA, τ=τ, nodef = nodef, noΔ = noΔ, rep_agent = rep_agent, ρz=ρz, σz=σz, ρξ=ρξ, σξ=σξ, wbar=wbar
		# , Nω=2,Nϵ=3,Nb=2,Nμ=2,Nσ=2,Nξ=2,Nz=3
		);
	try
		# h2 = load(pwd() * "/../Output/hank_backup.jld", "h")
		sd_old = load(pwd() * "/../Output/SOEdef.jld", "sd")
		print_save("\nFound generic JLD file")
		try
			sd_old = load(pwd() * "/../Output/run$(max(1,run_number-1))/SOEdef.jld", "sd") # set max(1, ...) to use run1 in first go
			print_save("\nFound JLD file from last run")
		catch
		end
		if N(sd,:ω) == N(sd_old,:ω) && N(sd,:ϵ) == N(sd_old,:ϵ)
			print_save(": loading previous results")
			sd.gr[:μ] = sd_old.gr[:μ]
			sd.gr[:σ] = sd_old.gr[:σ]
			sd.gr[:pN] = sd_old.gr[:pN]
			print_save("...")
			sd.ϕ = sd_old.ϕ
			sd.v = sd_old.v

			for (key, val) in sd_old.eq
				if haskey(sd.eq, key)
					sd.eq[:key] = val
				end
			end
			for (key, val) in sd_old.LoM
				if haskey(sd.LoM, key)
					sd.LoM[:key] = val
				end
			end
			
			if nodef
				print_save(" Not loading default policy.")
			else
				for (key, val) in sd_old.gov
					if haskey(sd.gov, key)
						sd.gov[:key] = val
					end
				end
			end
			print_save(" ✓")
		end
	catch
		print_save(": JLD file incompatible")
	end
	return sd
end

function eval_GMM(v_o, target_o; show_res::Bool=true)
	v_m = copy(v_o)
	targets = copy(target_o)

	targets[4] = targets[4] / targets[2]
	v_m[4] = v_m[4] / v_m[2]
	print("\nTargets ✓")

	W = diagm([1.0/targets[jj] for jj in 1:length(targets)])
	W[2,2] *= 100
	W[4,4] *= 50

	g = (v_m - targets)'*W*(v_m-targets)

	if show_res
		targetnames = ["AR(1) Output"; "σ(Output)"; "AR(1) Cons"; "σ(Cons) / σ(Output)"; "AR(1) Spreads"; "σ(spreads)"; "mean B/Y"; "std B/Y"; "mean unemp"; "std unemp"; "median Dom Holdings"; "mean wealth/Y" ]
		res = [targetnames v_m targets (targets-v_m)./targets]
		for jj in 1:size(res,1)
		    print_save("\n")
		    print_save(res[jj,1])
		    for ii in 2:size(res,2)
		    	print_save("     ")
		    	print_save("$(@sprintf("%0.3g",res[jj,ii]))")
		    end
		end
		print_save("\ng = $(@sprintf("%0.3g", g))")
	end
	print_save("\n")
	return g
end

function make_simulated_path(sd::SOEdef, savedir, years=100)
	pp, jz_series, Ndefs = simul(sd; simul_length=4*(years+25), burn_in=1+4*25)
	Tyears = floor(Int64,periods(pp)*0.25)
	def_freq = Ndefs/Tyears
	print_save("\n$Ndefs defaults in $Tyears years: default freq = $(floor(100*def_freq))%")
	save(savedir*"p_bench.jld", "pp", pp, "Ndefs", Ndefs)
	
	# pl = plot_simul(path)

	# pl, πthres = plot_episodes(path; episode_type="onlyspread", slides=true, πthres=0.95) # Also here need to make it so there are at least 10 episodes
	πthres = 1.0
	# make_IRF_plots(path; slides = true, create_plots = true, response = resp, savedir=savedir) # for resp = Y, C

	v_m = simul_stats(pp)
	targets = vec([0.96580506  0.01294576  0.96172496  0.01663608  0.96656486  0.10252351 64.57638889 23.48323041 15.94722222  6.08732167  56.4851069778397  94.479167])
	
	g = eval_GMM(v_m, targets)
	calib_table = make_calib_table(v_m)
	write(savedir * "calib_table.txt", calib_table)

	return g, pp, πthres, v_m, def_freq
end

function make_comparison_simul(sd::SOEdef, noΔ, rep_agent, run_number, years, p_bench::Path, episode_type, πthres, savedir)

	old_Δ = copy(sd.pars[:Δ])
	sim_mat = [ji==jj for ji in 1:3, jj in 1:3]
	sim_names = ["nodelta", "nodef", "nob"]

	freq, v = [zeros(3) for jj in 1:2]
	for (js, sim_name) in enumerate(sim_names)
		nodelta, nodef, nob = sim_mat[js, :]
		if sim_name == "nodelta"
			sd.pars[:Δ] = 0
		end
		try 
			pp, Ndefs = load("../Output/run$(run_number)/p_$(sim_name).jld", "pp", "Ndefs")
			print_save("\nFound $(sim_name) simul")
		catch
			sd = load("../Output/run$(run_number)/SOEdef.jld", "sd")
			print_save("\nSolving $(sim_name) version")
			mpe_iter!(sd; nodef = nodef, noΔ = nodelta, nob = nob, rep_agent = rep_agent, run_number=run_number, save_copies=false)
			pp, _, Ndefs = simul(sd; simul_length=4*(years+25), burn_in=1+4*25)
			save("../Output/run$(run_number)/p_$(sim_name).jld", "pp", pp, "Ndefs", Ndefs)
			print_save(" ✓")
		end
		sd.pars[:Δ] = old_Δ
		Tyears = floor(Int64,periods(pp)*0.25)
		freq[js] = Ndefs/Tyears
		v[js] = simul_stats(pp)
	end

	freq_nodelta, freq_nodef, freq_nob = freq
	v_nodelta, v_nodef, v_nob = v

	# for (jj, slides) in enumerate([true; false])
	# 	pcomp = plot_comparison_episodes(p_bench, p_nodef; episode_type = episode_type, slides = slides, πthres=πthres)
	# 	savejson(pcomp, savedir * "comparison_crisis_nodef$(jj).json")
	# end

	return v_noΔ, v_nodef, v_nob, freq_noΔ, freq_nodef, freq_nob
end
# 	pp, Ndefs = load("../Output/run$(run_number)/p_nodelta.jld", "pp", "Ndefs")

# 	h.Δ = old_Δ
# 	try 
# 		pp, Ndefs = load("../Output/run$(run_number)/p_nodef.jld", "pp", "Ndefs")
# 		print_save("\nFound nodef simul")
# 	catch
# 		print_save("\nSolving nodef version")
# 		h = load(savedir * "hank.jld", "h")
# 		mpe_iter!(h; nodef = true, noΔ = false, rep_agent = rep_agent, run_number=run_number, maxiter = 21, save_copies=false)
# 		pp, _, Ndefs = simul(h; simul_length=4*(years+25), only_def_end=false)
# 		save("../Output/run$(run_number)/p_nodef.jld", "pp", pp, "Ndefs", Ndefs)
# 		print_save(" ✓")
# 	end
# 	pp, Ndefs = load("../Output/run$(run_number)/p_nodef.jld", "pp", "Ndefs")
# 	freq_nodef = Ndefs/Tyears

# 	v_nodef = simul_stats(p_nodef)

# 	h.Δ = old_Δ
# 	try
# 		p_nob, Ndefs = load("../Output/run$(run_number)/p_nob.jld", "p_nob", "Ndefs")
# 		print_save("\nFound nob simul")
# 	catch
# 		print_save("\nSolving nob version")
# 		h = load(savedir * "hank.jld", "h")
# 		mpe_iter!(h; nodef = false, noΔ = false, rep_agent = rep_agent, run_number=run_number, maxiter = 21, save_copies=false, nob=true)
# 		p_nob, _, Ndefs = simul(h; simul_length=4*(years+25), only_def_end=false)
# 		save("../Output/run$(run_number)/p_nob.jld", "p_nob", p_nob, "Ndefs", Ndefs)
# 		print_save(" ✓")
# 	end
# 	p_nob, Ndefs = load("../Output/run$(run_number)/p_nob.jld", "p_nob", "Ndefs")
# 	freq_nob = Ndefs/Tyears

# 	v_nob = simul_stats(p_nob)

# end


# function make_something_else()
# 	savedir = pwd() * "/../Output/run$(run_number)/"
# 	save(savedir * "path.jld", "pp", pp)
	
# 	pl = plot_simul(path)
# 	savejson(pl, savedir * "path.json")	
# 	try
# 		savefig(savedir * "path.pdf")
# 	catch
# 	end

# 	pl, πthres = plot_episodes(path; episode_type="onlyspread", slides=true, πthres=0.95)
# 	savejson(pl, savedir * "onlyspread_slides.json")
# 	try
# 		savefig(savedir * "onlyspread_slides.pdf")
# 	catch
# 	end

# 	# pl = plot_episodes(path; episode_type="onlyspread", slides=false, πthres=0.975)
# 	# savejson(pl, savedir * "onlyspread_paper.json")

# 	for resp in ["C"; "Y"]
# 		try
# 			make_IRF_plots(path; slides = true, create_plots = true, response = resp, savedir=savedir)
# 		catch
# 		end
# 	end

# 	params = pars(h)

# 	try
# 		v_m = simul_stats(path)
# 		targetnames = ["AR(1) Output"; "σ(Output)"; "AR(1) Cons"; "σ(Cons) / σ(Output)"; "AR(1) Spreads"; "σ(spreads)"; "mean B/Y"; "std B/Y"; "mean unemp"; "std unemp"; "median Dom Holdings"; "mean wealth/Y" ]
# 		targets[4] = targets[4] / targets[2]
# 		v_m[4] = v_m[4] / v_m[2]
# 		print("\nTargets ✓")

# 		W = zeros(length(v_m),length(v_m))
# 		[W[jj,jj] = 1.0/targets[jj] for jj in 1:length(targets)]
# 		W[2,2] *= 100
# 		W[4,4] *= 50

# 		print("\nW ✓")
# 		g = (v_m - targets)'*W*(v_m-targets)
# 		print_save("\nObjective function = $(@sprintf("%0.3g",g))")
# 		print_save("\n")
# 		for jj in 1:length(targets)
# 			print_save("$(@sprintf("%0.3g",v_m[jj]))  ")
# 		end
# 		print_save("\nParams: ")
# 		for jj in 1:length(params)
# 			print_save("$(@sprintf("%0.3g",params[jj]))  ")
# 		end
# 		res = [targetnames v_m targets (targets-v_m)./targets]
# 		for jj in 1:size(res,1)
# 		    print_save("\n")
# 		    print_save(res[jj,1])
# 		    for ii in 2:size(res,2)
# 		    	print_save("     ")
# 		    	print_save("$(@sprintf("%0.3g",res[jj,ii]))")
# 		    end
# 		end
# 	catch
# 		print_save("\nWARNING: Found problems computing simulation statistics")
# 	end

# 	v_m[4] = v_m[4] * v_m[2]
# 	# save(savedir * "v_m.jld", "v_m", v_m)
# 	# write(savedir * "stats.txt", "$(v_m)")
	
# 	calib_table = make_calib_table(v_m)
# 	write(savedir * "calib_table.txt", calib_table)

# 	return g, path, πthres, v_m, def_freq
# end


pars(sd::SOEdef) = [(1/sd.pars[:β])^4-1; sd.pars[:γ]; sd.pars[:τ]; sd.pars[:wbar]; sd.pars[:ρz]; sd.pars[:σz]; sd.pars[:meanξ]; sd.pars[:ρξ]; sd.pars[:σξ]]

function make_center(params::Vector)

	rloc, RRA, τ, wbar, ρz,σz, tax, ρξ,σξ = params

	return [rloc; tax; RRA; τ; ρz; σz; ρξ; σξ; wbar]
end