return {
    ["default"] = {
        nofood = false,
        cellsNum = 100,
        denergy = 0.1,
        foodenergy = 10,
        gridSize = 100,
        threadCount = 1,
    },
    ["fast && infinite"] = {
        nofood = true,
        cellsNum = 20,
        denergy = 0.0,
        foodenergy = 10,
        gridSize = 30,
        threadCount = 1,
    },
    ["slow"] = {
        nofood = false,
        cellsNum = 200,
        denergy = 0.1,
        foodenergy = 10,
        gridSize = 100,
        threadCount = 1,
    },
}
