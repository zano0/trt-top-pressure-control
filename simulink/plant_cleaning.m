function m_c = plant_cleaning(p1, p2, P)
%PLANT_CLEANING Flow through dust catcher + bag filters from V1 (top) to V2 (header).
%   Quadratic resistance: p1 - p2 = k_clean * m_c^2 (flow reversal allowed, sign preserved).
%#codegen
dp  = p1 - p2;
m_c = sign(dp) * sqrt(abs(dp) / P.k_clean);
end
