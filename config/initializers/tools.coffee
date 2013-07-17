module.exports = (compound) ->
    app = compound.app

    compound.tools.database = ->
        {Alarm} = compound.models

        switch process.argv[3]
            when 'cleandb'
                Alarm.destroyAll ->
                    console.log 'All data cleaned'
                    process.exit 0
                break
            else
                console.log 'Usage: compound database [cleandb]'
                process.exit 0