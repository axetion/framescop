-- One-off function to read from a file.

function readFile(filename)
    local f = io.open(filename,'rb')
    if f then
        local lines = {}
        for line in io.lines(filename) do
            lines[#lines + 1] = line
        end
        return lines
    end
    
    print("ERROR: no file: " .. filename)
    return nil
end

return readFile