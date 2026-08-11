-- THE HOST'S MATRIX, in one place (roadmap T1.1).
--
-- Pure Lua: no love, no harness context, so the offline suite and the
-- laboratory can both use it and there is exactly one definition of what the
-- host does.
--
-- WHY THIS FILE EXISTS. The laboratory shows every option that changes the
-- MESH and hides every option that lives in the draw MATRIX (BREATH, SWAY,
-- MOTION LAG, FOOTFALL, ATTENTION, PART LAG), because in the lab there is no
-- host and no matrix. Giving it a synthetic one is what T1.1 is for, and the
-- risk it carries is specific: a fabricated matrix that does not match what the
-- host really builds produces a lab that shows a lie confidently.
--
-- The offline suite already reproduces this chain correctly and asserts the
-- result at four camera rungs. It did so with the construction written inline,
-- which meant the lab would have needed a SECOND copy, and the second copy is
-- the one that goes stale. So the construction moved here and both callers read
-- it.
--
-- THE CHAIN, and every step matters:
--
--   1. the mesh builders bake Rx(corr) into every vertex, where
--      corr = pi/2 - cameraAngle;
--   2. the host's model matrix undoes it, which is why `forRung` is
--      Rx(angle - pi/2);
--   3. the life channel post-multiplies in the middle, and has to CONJUGATE
--      to land in the character's axis rather than the camera's.
--
-- Skipping step 3 is not a rounding error. Measured before it was fixed: with
-- BREATH SUBTLE the head rose 33% of its advertised amount at the default rung,
-- 7% at the lowest and 93% at the highest, plus fore-and-aft drift nobody asked
-- for. An effect whose size depends on where the camera is is not an effect, it
-- is an accident of the assembly.

local M = {}

-- The Voxel Mod's own camera ladder, measured from top down. 0 lays the card
-- flat on the ground and 90 stands it upright, so the pitch above the horizon
-- is 90 - rung. These four are the ones the game actually visits.
M.RUNGS = { 15, 35, 50, 75 }

function M.rotX(t)
  local c, s = math.cos(t), math.sin(t)
  return { 1, 0, 0, 0,
           0, c, -s, 0,
           0, s,  c, 0,
           0, 0,  0, 1 }
end

-- The rotation the BUILDER bakes into each vertex, for a given camera rung.
function M.correction(rungDeg)
  return math.pi / 2 - math.rad(rungDeg)
end

-- The host's model matrix for a given camera rung: exactly what undoes the
-- baked rotation. This is the synthetic host the laboratory needs.
function M.forRung(rungDeg)
  return M.rotX(math.rad(rungDeg) - math.pi / 2)
end

-- Carry a point from CHARACTER coordinates into MESH space, the same way the
-- builder does. A caller that forgets this is comparing points that live in
-- different spaces and will read a difference that is not there.
function M.toMeshSpace(corr, x, y, z)
  local c, s = math.cos(corr), math.sin(corr)
  return x, y * c - z * s, y * s + z * c
end

function M.apply(m, x, y, z)
  return m[1] * x + m[2] * y + m[3] * z + m[4],
         m[5] * x + m[6] * y + m[7] * z + m[8],
         m[9] * x + m[10] * y + m[11] * z + m[12]
end

function M.mul(a, b)
  local r = {}
  for i = 0, 3 do
    for j = 1, 4 do
      r[i * 4 + j] = a[i * 4 + 1] * b[j]
                   + a[i * 4 + 2] * b[4 + j]
                   + a[i * 4 + 3] * b[8 + j]
                   + a[i * 4 + 4] * b[12 + j]
    end
  end
  return r
end

-- WHAT THE LIFE CHANNEL DID, expressed in mesh space.
--
-- The mod's draw wrap is handed the host matrix H and returns M'. The
-- difference between them is the life transform, and `H^-1 * M'` is that
-- difference in the space the harness's vertices already live in. H is a pure
-- rotation about x, so its inverse is the rotation by the negative angle: no
-- general inversion, no numerical drift.
--
-- THIS IS NOT A SECOND COPY OF `lifeApply`. Nothing here computes breath, sway,
-- lag, footfall or attention. The mod computes M' with its own shipped code and
-- this only asks what changed, which is the whole point: a preview built on a
-- reimplementation would agree with itself and disagree with the game.
--
-- The invariant that makes it safe to draw: with every life option off, the mod
-- returns M' = H, so this returns the identity and the preview cannot move
-- anything. That is asserted in the offline suite rather than assumed.
function M.lifeDelta(rungDeg, model)
  local inversa = M.rotX(-(math.rad(rungDeg) - math.pi / 2))
  return M.mul(inversa, model)
end

function M.isIdentity(m, tol)
  tol = tol or 1e-9
  local eye = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
  for i = 1, 16 do
    if math.abs(m[i] - eye[i]) > tol then return false end
  end
  return true
end

return M
