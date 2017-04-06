$ ->
  sock = new WebSocket "wss#{location.href.substring 5, location.href.lastIndexOf '/'}"
  sock.onopen = ->
    sock.send "\"#{sessid}\""
    $(".contentlink[href='#{location.hash}']").click()
    sock.onclose = ->
      unless window.preventSocketAlert
        alert 'the websocket has been disconnected, reloading the page'
        document.location.reload()
    sock.onmessage = (event) ->
      msg = JSON.parse event.data

      if msg.type is 'done'
        self = $("input[data-chalid='#{msg.subject}']")
        self.prop 'checked', msg.data
        self.parent().next().css 'text-decoration', if msg.data then 'line-through' else 'none'
        if msg.data
          self.parent().parent().addClass 'done'
        else
          self.parent().parent().removeClass 'done'
        updateProgress()

      else if msg.type is 'assign'
        self = $(".labels[data-chalid='#{msg.subject}']")
        if msg.data[1]
          self.append $("<li />").append($("<span />").addClass("label").attr("data-name", msg.data[0].name).text(msg.data[0].name))
        else
          self.find(".label[data-name='#{msg.data[0].name}']").parent().remove()
        $(".assignment-count[data-chalid='#{msg.subject}']").text self.first().find('.label').length

      else if msg.type is 'ctfmodification'
        $('#ctfmodification').fadeIn 500

      else if msg.type is 'login'
        $('#userlist').append $("<li />").text(msg.data)
        $('#usercount').text $('#userlist').children('li').length

      else if msg.type is 'logout'
        $("#userlist li:contains('#{msg.data}')").remove()
        $('#usercount').text $('#userlist').children('li').length
        $(".active-user[data-name='#{msg.name}']").remove

      else if msg.type is 'fileupload' or msg.type is 'filedeletion'
        if "#{msg.data}files" is window.currentPage
          current = window.currentPage
          window.currentPage = null
          $(".contentlink[href='##{current}']").click()
        subject = $(".contentlink[href='##{msg.data}files']")
        if msg.filecount > 0
          subject.children('i').removeClass('icon-folder-close').addClass('icon-folder-open')
        else
          subject.children('i').removeClass('icon-folder-open').addClass('icon-folder-close')
        subject.nextAll('sup').text msg.filecount

      else if msg.type is 'setactive'
        $(".active-user[data-name='#{msg.name}']").remove()
        if msg.challenge isnt undefined
          $("#activeUsers#{msg.challenge}").append($('<span />')
            .addClass('active-user')
            .css('background-color', msg.color)
            .attr('data-name', msg.name)
            .text(msg.name))

      else if msg.type is 'chat'
        self = $('#chats')
        for msgData in msg.data
          user = if msgData.name then msgData.name else msgData.user
          self.append(
              $("<tr />").css("width", "100%").append(
                $("<td />").css("width", "100%").append(
                  $("<span />").addClass("label label-default").css("background-color", msgData.color).text(user)).append(
                  $("<p />").css("display", "inline").text(" " + msgData.message))).append(
                $("<td />").attr("valign", "top").css("padding-right", "1px").append(
                  $("<i />").text(msgData.time.substring(11,19)))));
        if $("#chat-scroll").prop 'checked'
            $(".chat-body").animate { scrollTop: $(".chat-body").prop "scrollHeight" }

      else if msg.type is 'setimpact'
        console.log msg
        chal = $(".challenge[data-challengeid=#{msg.id}]")
        chal.attr('data-impactvalue', msg.value)
          .find('option').attr('selected', false)
        chal.find("option[value=#{msg.name}]").attr('selected', true)
        window.updatePriority()
      else
        alert event.data
      #TODO handle events

  window.onbeforeunload = ->
    window.preventSocketAlert = true
    return

  sessid = $.cookie 'ctfpad'
  if $.cookie('ctfpad_hide') is undefined then $.cookie 'ctfpad_hide', 'false'

  updateProgress = ->
    #challenge progress
    d = $('.challenge.done').length / $('.challenge').length
    $('#progress').css 'width', "#{d*100}%"
    $('#progress').siblings('span').text "#{$('.challenge.done').length} / #{$('.challenge').length}"
    #score progress
    totalScore = 0
    score = 0
    $('.challenge').each ->
      totalScore += parseInt($(this).attr 'data-chalpoints')
      if $(this).hasClass 'done' then score += parseInt($(this).attr 'data-chalpoints')
    $('#scoreprogress').css 'width', "#{(score/totalScore)*100}%"
    $('#scoreprogress').siblings('span').text "#{score} / #{totalScore}"
    #categories progress
    $('.category').each ->
      cat = $(this).attr 'data-category'
      done = $(this).siblings(".done[data-category='#{cat}']").length
      $(this).find('.done-count').text done

  updateProgress()

  window.uploads = []

  window.upload_refresh = (remove) ->
    if remove
      window.uploads.splice(window.uploads.indexOf(remove), 1)
      if window.uploads.length == 0
        $('#uploadbutton').hide()
        return
    total_size = total_prog = 0
    for upload in window.uploads
      total_size += upload.file.size
      total_prog += upload.progress
    progress = parseInt(total_prog / total_size * 100, 10)
    $('#uploadprogress').text "#{progress}% / #{window.uploads.length} files"

  window.upload_handler_send = (e, data) ->
    if window.uploads.length == 0
      $('#uploadbutton').show()
    data.context =
      file: data.files[0]
      progress: 0
    window.uploads.push data.context
    window.upload_refresh()

  window.upload_handler_done = (e, data) ->
    window.upload_refresh(data.context)

  window.upload_handler_fail = (e, data) ->
    window.upload_refresh(data.context)
    alert "Upload failed: #{data.errorThrown}"

  window.upload_handler_progress = (e, data) ->
    data.context.progress = data.loaded
    window.upload_refresh()


  $('.contentlink').click ->
    page = $(this).attr('href').replace '#', ''
    unless window.currentPage is page
      if m = /^(ctf|challenge)(.+)files$/.exec(page)
        $('#content').html ""
        $.get "/files/#{m[1]}/#{m[2]}", (data) ->
          $('#content').html data
          url = "/upload/#{m[1]}/#{m[2]}"
          $('#fileupload').fileupload({
            url: url,
            dataType: 'json',
            send: window.upload_handler_send,
            done: window.upload_handler_done,
            fail: window.upload_handler_fail,
            progress: window.upload_handler_progress
          }).prop('disabled', !$.support.fileInput).parent().addClass $.support.fileInput ? undefined : 'disabled'
      else
        $('#content').pad {'padId':page, color: window.user.color}
      $(".highlighted").removeClass("highlighted")
      $(this).parents(".highlightable").addClass("highlighted")
      chalid = $(this).parents(".highlightable").attr("data-challengeid")
      if chalid isnt undefined
        sock.send JSON.stringify {type: 'setactive', subject: parseInt chalid}
      window.currentPage = page

  $("input[type='checkbox']").change ->
    $(this).parent().next().css 'text-decoration',if this.checked then 'line-through' else 'none'
    sock.send JSON.stringify {type:'done', subject:parseInt($(this).attr('data-chalid')), data:this.checked}
    window.updatePriority()

  $('.impact').popover({
    html:true,
    content: -> $(this).parent().find('.popover-content').html()
  }).click (e)->
    $('.impact').not(this).popover('hide')
    $(this).popover 'toggle'
    e.stopPropagation()

  $('html').click ->
    $('.impact').popover('hide')

  window.setImpact = (chalId, impact) ->
    sock.send JSON.stringify {
      type: 'setimpact',
      impact: impact,
      id: chalId
    }

  $('body').delegate 'select[name=impact]', 'change', ->
    self = $(this)
    window.setImpact self.attr('data-chalid'), self.val()

  $('.scoreboard-toggle').popover {html: true, content: ->
    $.get '/scoreboard', (ans) -> #FIXME function gets executed twice?
      $('#scoreboard').html(ans)
    , 'html'
    return '<span id="scoreboard">loading...</span>'
  }

  $('body').delegate '.btn-assign', 'click', ->
    sock.send JSON.stringify {type:'assign', subject:parseInt($(this).attr('data-chalid'))}

  $('body').delegate '.add-challenge', 'click', ->
    a = $(this).parent().clone()
    a.find('input').val('').removeClass 'hide'
    $(this).parent().after a
    if a.hasClass 'dummy'
      a.removeClass('dummy')
      $(this).parent().remove()

  $('body').delegate '.remove-challenge', 'click', ->
    if $('.category-formgroup').length > 1 then $(this).parent().remove()

  $('body').delegate '.deletefile', 'click', ->
    fileid = $(this).attr('data-id')
    filename = $(this).attr('data-name')
    $('#deletefilemodal .alert').removeClass('alert-success alert-error').hide()
    $('#deletefilename').text filename
    $('#deletefilebtnno').text 'no'
    $('#deletefilebtnyes').show()
    $('#deletefilemodal').data('fileid', fileid).modal 'show'
    return false

  $('body').delegate '.btn-chat', 'click', ->
    mymessage = $('.form-chat-send').val()
    $('.form-chat-send').val ""
    sock.send JSON.stringify {
      type: 'chat',
      message: mymessage
    }

  $('body').delegate '.form-chat-send', 'keypress', (event) ->
    keycode = if event.keyCode then event.keyCode else event.which
    if keycode is 13 or keycode is '13'
      mymessage = $('.form-chat-send').val()
      $('.form-chat-send').val ""
      sock.send JSON.stringify {
        type: 'chat',
        message: mymessage
      }
  
  $('body').delegate '.hide-cat-btn', 'click', ->
    self = $(this)
    cat = self.attr('data-category')
    rows = $('tr.challenge[data-category="' + cat + '"')
    rows.toggleClass('hidden')
    self.toggleClass('glyphicon-collapse-down')
    self.toggleClass('glyphicon-expand')


  $('#hidefinished').click ->
    unless $(this).hasClass 'active'
      $('head').append '<style id="hidefinishedcss">.done { display:none; }</style>'
      $.cookie 'ctfpad_hide', 'true'
    else
      $('#hidefinishedcss').remove()
      $.cookie 'ctfpad_hide', 'false'
  if $.cookie('ctfpad_hide') is 'true' then $('#hidefinished').click()

  window.updatePriority = ->
    max = 0
    chals = $('.challenge')

    priority = (chal) ->
      if chal.find('input[type=checkbox]').prop('checked')
        return 0
      chal.attr('data-impactvalue') * chal.attr('data-chalpoints')

    chals.each ->
      max = Math.max(max, priority($(this)))

    chals.each ->

      self = $(this);
      challengeId = self.attr('data-challengeid')
      checked = self.find('input[type=checkbox]').prop('checked')
      cellToColor = self.children().eq(1)

      if checked
        cellToColor.css {
          'background': 'transparent',
          'text-decoration': 'line-through'
        }
      else
        pct = priority(self) / max * 100
        color = 'rgba(46, 204, 113, .5)'
        if pct > 85
          color = 'rgba(255, 0, 0, .7)'
        else if pct > 60
          color = 'rgba(255, 110, 0, .7)'
        gradientStyle = "#{color} #{pct}%,transparent #{pct}%, transparent 100%"

        style = [
            "background: -webkit-linear-gradient(left, #{gradientStyle})",
            "background: -o-linear-gradient(right, #{gradientStyle})",
            "background: -moz-linear-gradient(right, #{gradientStyle})",
            "background: linear-gradient(to right, #{gradientStyle})"
        ].join(';')
        cellToColor.attr 'style', style
      #console.log self.attr('data-challengeid'), self.width(), self.height(), self.position()

  window.updatePriority()

  window.newctf = ->
    l = $('#ctfform').serializeArray()
    newctf = {title: l.shift().value, challenges:[]}
    until l.length is 0
      newctf.challenges.push {'title':l.shift().value, 'category':l.shift().value, 'points':parseInt(l.shift().value)}
    sock.send JSON.stringify {type:'newctf', data: newctf}
    $('#ctfmodal').modal 'hide'
    $('#ctfform').find('input').val ''
    document.location = '/scope/latest'

  window.ajaxPost = (url, data = null, cb) -> $.ajax

  window.changepw = ->
    $.ajax {
      url: '/changepassword'
      type: 'post'
      data: $('#passwordform').serialize()
      dataType: 'json'
      headers:
        'x-session-id': $.cookie('ctfpad')
      success: (ans) ->
        $('#passwordmodal .alert').removeClass('alert-success alert-error')
        if ans.success
          $('#passwordmodal .alert').addClass('alert-success').text 'your password has been changed'
        else
          $('#passwordmodal .alert').addClass('alert-error').text ans.error
        $('#passwordmodal .alert').show()
    }

  window.newapikey = ->
    $.ajax {
      url: '/newapikey'
      type: 'post'
      dataType: 'text'
      headers:
        'x-session-id': $.cookie('ctfpad')
      success: (apikey) ->
        if apikey then $('#apikey').text apikey
    }

  window.modifyctf = ->
    l = $('#ctfmodifyform').serializeArray()
    ctf = {ctf: window.current.id, challenges:[]}
    until l.length is 0
      ctf.challenges.push {'id':parseInt(l.shift().value), 'title':l.shift().value, 'category':l.shift().value, 'points':parseInt(l.shift().value)}
    sock.send JSON.stringify {type:'modifyctf', data: ctf}
    $('#ctfmodifymodal').modal 'hide'
    setTimeout ->
      document.location.reload()
    ,500

  window.delete_file_confirmed = () ->
    $.get '/delete_file/' + $('#deletefilemodal').data('fileid'), (ans) ->
      $('#deletefilemodal .alert').removeClass('alert-success alert-error')
      if ans.success
        $('#deletefilemodal .alert').addClass('alert-success').text 'file has been deleted'
      else
        $('#deletefilemodal .alert').addClass('alert-error').text ans.error
      $('#deletefilemodal .alert').show()
      $('#deletefilebtnno').text('close')
      $('#deletefilebtnyes').hide()
    ,'json'

