local ffi = require('ffi')
local table = require('table')
local math = require('math')

local block = require('radio.core.block')
local types = require('radio.types')

local BinaryPhaseCorrectorBlock = block.factory("BinaryPhaseCorrectorBlock")

function BinaryPhaseCorrectorBlock:instantiate(num_samples, sample_interval)
    self.num_samples = num_samples
    self.sample_interval = sample_interval or 32

    self.sample_index = 0
    self.phi_state = types.Float32.vector(self.num_samples)
    self.phi_moving_average = 0.0

    self:add_type_signature({block.Input("in", types.ComplexFloat32)}, {block.Output("out", types.ComplexFloat32)})
end

ffi.cdef[[
void *memmove(void *dest, const void *src, size_t n);
]]

function BinaryPhaseCorrectorBlock:process(x)
    local out = types.ComplexFloat32.vector(x.length)

    for i = 0, x.length-1 do
        if i == self.sample_index then
            -- Calculate angle of this sample
            local phi = x.data[i]:arg()

            -- Clamp the angle to the right quadrants
            phi = (phi < -math.pi/2) and (phi + math.pi) or phi
            phi = (phi > math.pi/2) and (phi - math.pi) or phi

            -- Pop last element of our table
            local last_phi = self.phi_state.data[0].value
            -- Shift the state samples down
            ffi.C.memmove(self.phi_state.data[0], self.phi_state.data[1], (self.phi_state.length-1)*ffi.sizeof(self.phi_state.data[0]))
            -- Insert phi sample into state
            self.phi_state.data[self.phi_state.length-1].value = phi

            -- Update the moving average
            self.phi_moving_average = self.phi_moving_average + phi/self.num_samples - last_phi/self.num_samples

            -- Update sample index
            self.sample_index = self.sample_index + self.sample_interval
        end

        -- Adjust the phase of this sample with the moving average
        out.data[i] = x.data[i] * types.ComplexFloat32(math.cos(-self.phi_moving_average), math.sin(-self.phi_moving_average))
    end

    -- Wrap sample index
    if self.sample_index >= x.length then
        self.sample_index = self.sample_index - x.length
    end

    return out
end

return BinaryPhaseCorrectorBlock
