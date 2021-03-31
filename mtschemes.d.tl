global type MtSchema = record
    --[[
    left, right, up, down
    ]]
    l: integer
    r: integer
    u: integer
    d: integer
    draw: {integer, integer}
end
return {MtSchema}
