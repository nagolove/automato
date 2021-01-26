global type MtSchema = record
    --[[
    left, right, up, down
    ]]
    l: number
    r: number
    u: number
    d: number
    draw: {number, number}
end
return {MtSchema}
