include("main_serial.jl")

write("../Output/output.txt", "")
sd = load("../Output/SOEdef1.jld", "sd")
sd = SOEdef()
update_probs!(sd)

mpe_iter!(sd, run_number = 1)

g, p_bench, _, v_m, def_freq = make_simulated_path(sd, "../Output/run1/", 30000);
Wr = mean([mean(series(p, :Wr)) for p in p_bench])

for (key, val) in pars(sd)
	print_save("$(rpad(key, 6, " ")) => $val\n")
end

save("../Output/SOEdef1.jld", "sd", sd, "g", g, "pp", p_bench, "pars", pars(sd), "Wr", Wr)
print_save("$(sd.gr[:z])\n")

for (key, val) in pars(sd)
	sd.pars[key] = val
end
update_probs!(sd)
mpe_iter!(sd, run_number = 2, nodef = true)
g, p_nodef, _, v_m, def_freq = make_simulated_path(sd, "../Output/run2/", 30000);
Wr = mean([mean(series(p, :Wr)) for p in p_nodef])

print_save("$(sd.gr[:z])\n")
save("../Output/SOEdef_nodef.jld", "sd", sd, "g", g, "pp", p_nodef, "pars", pars(sd), "Wr", Wr)

# g, p_benchnodef, _, _, _ = make_simulated_path(sd, "../Output/run5/", 30000, ϕ = sd2.ϕ);
# Wr = mean([mean(series(p, :Wr)) for p in p_benchnodef])
# save("../Output/SOEdef_benchnodef.jld", "g", g, "pp", p_benchnodef, "Wr", Wr)


# sd3 = load("../Output/SOEdef.jld", "sd")
# for (key, val) in pars(sd)
# 	sd3.pars[key] = val
# end
# update_probs!(sd3)
# mpe_iter!(sd3, run_number = 3, nodef = false, noΔ = true)
# g, p_noΔ, _, v_m, def_freq = make_simulated_path(sd3, "../Output/run3/", 30000);
# Wr = mean([mean(series(p, :Wr)) for p in p_noΔ])
# save("../Output/SOEdef_nodelta.jld", "sd", sd3, "g", g, "pp", p_noΔ, "pars", pars(sd3), "Wr", Wr)

# sd4 = load("../Output/SOEdef.jld", "sd")
# for (key, val) in pars(sd)
# 	sd4.pars[key] = val
# end
# update_probs!(sd4)
# mpe_iter!(sd4, run_number = 4, nodef = false, noΔ = false, nob = true)
# g, p_nob, _, v_m, def_freq = make_simulated_path(sd4, "../Output/run4/", 30000);
# Wr = mean([mean(series(p, :Wr)) for p in p_nob])
# save("../Output/SOEdef_nob.jld", "sd", sd4, "g", g, "pp", p_nob, "pars", pars(sd4), "Wr", Wr)


