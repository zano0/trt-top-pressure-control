function R = run_one(SCN, T, X0, C, P)
%RUN_ONE Simulate trt_model once and return the decoded log.
in = Simulink.SimulationInput('trt_model');
in = in.setVariable('P', P).setVariable('C', C).setVariable('X0', X0).setVariable('SCN', SCN);
in = in.setModelParameter('StopTime', num2str(T));
R = read_log(sim(in), P);
end
