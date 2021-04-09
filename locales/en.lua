return {
    language = "English", 
    en = {

        formatMods = {
            allEated = 'bla-bla-bla',
            maxEnergy = 'bla-bla-bla',
            minEnergy = 'bla-bla-bla',
            midEnergy = 'bla-bla-bla',
            cells = 'bla-bla',
            iterations = 'bla-bla',
            meals = 'bla-bla',
            born = 'bla-bla',
            died = 'bla-bla',
            percentAreaFilled = 'bla-bla',
            stepsPerSecond = 'bla-bla',
        },

        nofood = 'no food',
        initpopulation = 'initial population',
        invemmspeed = 'inverted emmision speed',
        decreaseenby = 'decrease energy by',
        foodenergy = 'food energy',
        gridsize = 'grid size',
        threadcount = 'thread count',
        startinsmode = 'start in step mode',
        start = 'start',
        changemode = 'change mode',
        stp = 'stp',
        readstate = 'read state',
        writestate = 'write state',
        nextplay = 'next play',
        exit = 'exit',
        progress = 'see progress',

        stat = {
            -- съедено клеток
            allEated = 'all cell eated',
            -- максимальная энергия клетки
            maxEnergy = 'maximum cell energy',
            -- минимальная энергия клетки
            minEnergy = 'minimal cell energy',
            -- среднее значение энергии клеток
            midEnergy = 'median cells energy',
            -- количество клеток
            cells = 'cells number',
            -- сделано циклов
            iterations = 'cycles done',
            -- количество клеток еды
            meals = 'nutrition amount',
            -- количество рожденных клеток
            born = 'born cells',
            -- количество умерших клеток
            died = 'died cells',
            -- процент заполнения площади поля
            percentAreaFilled = 'area filled %',
        },

        pos = "Position", -- пространство(??)
        position = "Position", 
        sound = "Sound",
        form = "Form",
        color = "Color",

        stat = "Statistic",
        mainMenu = {
            play = "play",
            viewProgress = "view progress",
            help = "help",
            exit = "exit",
        },
        setupMenu = {
            start = "Start",
            expTime = "Exposition time ",
            expTime_sec = " sec.",
            diffLevel = "Difficulty level: ",
            dimLevel = "Dim level: ", -- разница между размерностью и размером поля.

            expTime_plural = {
                one = "Exposition time %{count} second",
                few = "Exposition time %{count} seconds",
                many = "Exposition time %{count} seconds",
                other = "Exposition time %{count} seconds",
            },
        },

        waitFor = {
            one = "Wait for %d second",
            few = "Wait for %d seconds",
            many = "Wait for %d seconds",
        },

        settingsBtn = "Settings",
        --backToMainMenu = "Back to menu",
        backToMainMenu = "Main menu",
        --quitBtn = "Back to main", -- лучше назвать - "в главное меню?"
        quitBtn = "Main menu", -- лучше назвать - "в главное меню?"

        nodata = "No fineshed games yet. Try to play.",
        today = "today",
        yesterday = "yesterday",
        twoDays  = "two days ago",
        threeDays  = "three days ago",
        fourDays  = "four days ago",
        fiveDays = "five days ago",
        sixDays = "six days ago",
        lastWeek  = "last week",
        lastTwoWeek  = "last two week",
        lastMonth  = "last month",
        lastYear  = "last year",
        moreTime = "more year ago",

        levelInfo1_part1 = {
            one = "Duration %{count} minute", 
            few = "Duration %{count} minutes",
            many = "Duration %{count} minutes",
            other = "Duration %{count} minutes",
        },
        levelInfo1_part2 = {
            one = "%{count} second",
            few = "%{count} seconds",
            many = "%{count} seconds",
            other = "%{count} seconds",
        },

        levelInfo2_part1 = "Level %{count}",
        levelInfo2_part2 = {
            one = "Exposition %{count} second",
            few = "Exposition %{count} seconds",
            many = "Exposition %{count} seconds",
            other = "Exposition %{count} seconds",
        },

        help = {
            backButton = "Back to main menu",
            desc = [[Single n-back task with visual stimuli.
The n-back task is a continuous performance task that is commonly used as an assessment in psychology and cognitive neuroscience to measure a part of working memory and working memory capacity.[1] The n-back was introduced by Wayne Kirchner in 1958.[2] Some researchers have argued that n-back training may increase IQ, but evidence is low quality and mixed]],
        },

    },
}

