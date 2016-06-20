EventPopoverScreenView = require 'views/event_popover_screen'
random = require 'lib/random'

module.exports = class GuestPopoverScreen extends EventPopoverScreenView

    screenTitle: ''
    templateContent: require 'views/templates/popover_screens/guests'

    templateGuestRow: require 'views/templates/popover_screens/guest_row'

    events:
        "click .add-new-guest"          : "onNewGuest"
        "click .guest-delete"           : "onRemoveGuest"
        "click .guest-share-with-cozy"  : "onShare"
        "click .guest-share-with-email" : "onEmail"
        'keyup input[name="guest-name"]': "onKeyup"

    initialize: (options) ->
        super options

        @listenTo @formModel, 'change:shareID', =>
            @afterRender()

    getRenderData: ->

        # Override the screen title based on the model's value.
        guests = @formModel.get('attendees') or []
        numGuests = guests.length
        if numGuests > 0
            @screenTitle = t('screen guest title', smart_count: numGuests)
        else
            @screenTitle = t('screen guest title empty')

        return _.extend super(),
            guests: @formModel.get('attendes') or []
            readOnly: @context.readOnly


    afterRender: ->
        $guests = @$ '.guests'

        @formModel.fetchAttendeesStatuses (err, attendees) =>
            @renderAttendees $guests, attendees

    renderAttendees: ($guestElement, attendees) ->
        # Remove the existing elements of the list.
        $guestElement.empty()

        # Create a list item for each alert.
        if attendees
            for guest, index in attendees
                options = _.extend guest, {index}
                row = @templateGuestRow _.extend guest, readOnly: @context.readOnly
                $guestElement.append row

        if not @context.readOnly

            @configureGuestTypeahead()

            # Focus the form field. Must be done after the typeahead
            # configuration, otherwise bootstrap bugs somehow.
            @$('input[name="guest-name"]').focus()


    # Configure the auto-complete on contacts.
    configureGuestTypeahead: ->
        @$('input[name="guest-name"]').typeahead
            source: app.contacts.asTypeaheadSource()
            matcher: (contact) ->
                old = $.fn.typeahead.Constructor::matcher
                return old.call this, contact.display
            sorter: (contacts) ->
                beginswith = []
                caseSensitive = []
                caseInsensitive = []

                while (contact = contacts.shift())
                    item = contact.display
                    if not item.toLowerCase().indexOf(this.query.toLowerCase())
                        beginswith.push contact
                    else if ~item.indexOf this.query
                        caseSensitive.push contact
                    else caseInsensitive.push contact

                return beginswith.concat caseSensitive, caseInsensitive

            highlighter: (contact) ->
                old = $.fn.typeahead.Constructor::highlighter
                imgPath = if contact.hasPicture
                    "contacts/#{contact.id}.jpg"
                else
                    "img/defaultpicture.png"
                img = '<img width="40px" src="' + imgPath + '" />&nbsp;'
                return img + old.call this, contact.display

            updater: @onNewGuest.bind(@)


    onRemoveGuest: (event) ->
        # Get which guest to remove.
        index = @$(event.target).parents('li').attr 'data-index'

        # Remove the guest.
        guests = @formModel.get('attendees') or []
        guests.splice index, 1
        @formModel.set 'attendees', guests

        # Inefficient way to refresh the list, but it's okay since it will never
        # be a big list.
        @render()


    # Sharing an invitation directly between Cozy instances.
    onShare: (event) =>
        # Get the guest
        index = @$(event.target).parents('li').attr 'data-index'
        # Remove duplicate if any and refresh the view.
        @removeIfDuplicate index, true


    # If the user want to revert back to sharing the invitation using an email
    # instead of the guest Cozy.
    onEmail: (event) =>
        # Get the guest
        index = @$(event.target).parents('li').attr 'data-index'
        # Remove duplicate if any and refresh the view.
        @removeIfDuplicate index, false


    # Remove any duplicate: this function looks for a guest who is "identical"
    # to the one the user wants a switch. To be identical means to use the same
    # channel (email or share) to send the event. If a duplicate is found then
    # the guest for whom the user wanted a switch is removed from the guest
    # list.
    #
    # This function also refreshes the view.
    #
    # Parameters:
    #   * index: the index of the guest in the `guests` array;
    #   * share: a boolean to tell if the user wants to switch from email to
    #            share (true) or from share to email (false).
    removeIfDuplicate: (index, share) ->
        guests = @formModel.get('attendees') or []
        # A clone is required in order to refresh the view.
        guests = _.clone guests
        guest  = guests[index]
        # We remove the guest from the list to find a possible duplicate.
        guests.splice index, 1

        if share
            guestBis = _.findWhere(guests, cozy: guest.cozy)
        else
            guestBis = _.findWhere(guests, email: guest.email)

        # If the switch is email -> share then the parameter `share` is true
        # hence the label is the guest's cozy; if the switch is share -> email
        # then `share` is false and the label is the guest's email.
        guest.share = share
        guest.label = if share then guest.cozy else guest.email

        # If there is no duplicate the guest is added back to its original spot.
        if (not guestBis?) or (share and (not guestBis.share)) or
        ((not share) and guestBis.share)
            guests.splice index, 0, guest

        @formModel.set 'attendees', guests
        # Force refresh the view.
        @render()


    # Handle guest addition. `userInfo` is passed when called by the typeahead.
    onNewGuest: (userInfo = null) ->

        # Autocomplete was used.
        if userInfo? and typeof(userInfo) is "string"
            [channel, contactID] = userInfo.split(';')
        # Field was entered manually.
        else
            channel   = @$('input[name="guest-name"]').val()
            contactID = null

        # Determine if guest's "channel" of communication is the url of his cozy
        # or his mail address.
        if (channel.indexOf "@") < 0
            cozy  = channel
        else
            email = channel
            # An empty value should not be submitted.
            email = email.trim()

        if email?.length > 0 or cozy?.length > 0
            guests = @formModel.get('attendees') or []

            # Look for a duplicate:
            # * another guest with the same email;
            if email?
                guestBisEmail = _.findWhere(guests, email: email)
            # * another guest with the same cozy;
            if cozy?
                guestBisCozy  = _.findWhere(guests, cozy: cozy)

            # But a duplicate is not a duplicate under certain circumstances:
            # * same email and `shareWithCozy` is true;
            # * same cozy and `shareWithCozy` is false;
            # In those cases we can add the new guest.
            if (email? and (not guestBisEmail? or
            guestBisEmail?.shareWithCozy)) or (cozy? and (not guestBisCozy? or
            (not guestBisCozy?.shareWithCozy)))
                newGuest =
                    key       : random.randomString()
                    status    : 'INVITATION-NOT-SENT'
                    contactid : contactID

                # If guest was "autocompleted" then contactID is not null. We
                # can fill additionnal information.
                if contactID?
                    contact       = app.contacts.get contactID
                    newGuest.name = contact.get 'name'
                    if email?
                        newGuest.email         = email
                        newGuest.label         = email
                        # By default if a guest has several cozy linked to him,
                        # the first one is chosen.
                        newGuest.cozy          =
                            (contact.get 'cozy')?[0]?.value or null
                        newGuest.shareWithCozy = false
                    else if cozy?
                        emails                 = (contact.get 'emails')
                        # By default if a guest has several emails linked to
                        # him, the first one is chosen.
                        newGuest.email         = emails?[0]?.value or null
                        newGuest.label         = cozy
                        newGuest.cozy          = cozy
                        newGuest.shareWithCozy = true
                # Guest was manually entered
                else
                    if email?
                        newGuest.label         = email
                        newGuest.email         = email
                        newGuest.shareWithCozy = false
                        newGuest.cozy          = null
                    else
                        newGuest.label         = cozy
                        newGuest.email         = null
                        newGuest.shareWithCozy = true
                        newGuest.cozy          = cozy

                # Clone the source array, otherwise it's not considered as
                # changed because it changes the model's attributes
                guests = _.clone guests
                guests.push newGuest
                @formModel.set 'attendees', guests

                # Inefficient way to refresh the list, but it's okay since
                # it will never be a big list.
                @render()

        # Reset form field.
        @$('input[name="guest-name"]').val ''
        @$('input[name="guest-name"]').focus()


    onKeyup: (event) ->
        key = event.keyCode
        if key is 13 # enter
            @onNewGuest()

