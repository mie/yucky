String.prototype.trunc = String.prototype.trunc ||
  function(n){
      return this.length>n ? this.substr(0,n-1)+'...' : this;
  };

var loading = false;
var end_reached = false;
var page = 1;
var calendar = null;
    
function load_data(obj = {}) {
  // var query = '/json/books?page='+page;
  // if(opts['subreddit']){
  //   query += '&subreddit='+opts['subreddit'];
  // }
  /*
  $.getJSON(query, function(data){
    if(data.books.length == 0){
      end_reached = true;
    }else{
      show_data(data);
    }
  });*/
  obj['page'] = page;
  $.ajax({
    url: "/json/search",
    type: 'post',
    dataType: 'json',
    data: JSON.stringify(obj),
    success: function(data){
      if(!data.query){
        var events = [];
        $.each(data.dates, function(i, d){
          events.push({date: d.split(' ').join('-')});
        });
        calendar.setEvents(events);
      }
      if(data.books.length == 0){
        end_reached = true;
      }else{
        show_data(data);
      }
    },
    error: function(e){
      console.log('error');
    }
  });
  loading = false;
  $(".loading").remove();
  return false;
}

function show_data(d){
  if(page == 1){
    $('div#content').empty();
  }
  if(d.query == 'date'){
    $('#sel-date').text(d.dates[0]);
    $('#sel-subreddits').text('All');
  }
  if(d.query == 'subreddit'){
    $('#sel-date').text('Any');
    $('#sel-subreddits').text(d.subreddits[0]);
  }
  $.each(d.books, function(index, b){
    var n = $('<div>', {class: 'row book', id: b.reddit_id});
    var p = $('<div>', {class: 'col-lg-12'});
    /*p.append($('<h2>', {class: 'beta'}).append(
        $('<span>', {class: 'label label-danger', text: '/r/'+b.subreddit})
      ));*/
    if(b.over_18 == true){
      p.append($('<h1>', {class: 'alpha nsfw', text: b.title}));
    }else{
      p.append($('<h1>', {class: 'alpha', text: b.title}));
    }
    p.append($('<a>', {class: 'close delete-book', href: "#"}).append($('<i>', {class: 'icon-cancel-circled2'})));
    p.append(
      $('<h2>').append(
        //$('<span>', {class: 'label label-info', text: b.subreddit})
        $('<span>').append($('<i>', {class: 'icon-info-circled'}))
      ).append(
        $('<ul>', {class: 'list-inline info'}).append(
          $('<li>', {text: '/r/'+b.subreddit})
        ).append(
          $('<li>', {text: 'comments: '+b.num_comments})
        ).append(
          $('<li>', {text: 'score: '+b.score})
        ).append(
          $('<li>').append(
            $('<a>', {text: 'EPUB: '+humanFileSize(b.epub_size, true), href: "/books/epub/"+b.reddit_id})
          )
        ).append(
          $('<li>').append(
            $('<a>', {text: 'MOBI: '+humanFileSize(b.mobi_size, true), href: "/books/mobi/"+b.reddit_id})
          )
        )
      )
    );
    n.append(p);
    $('div#content').append(n);
  });
}

function show_subreddits(data){
  var pr = $('#cbp-spmenu-s1');
  pr.empty();
  pr.append($('<h3>', {text: 'Subreddits'}));
  $.each(data.subreddits, function(index, s){
    pr.append($('<a>', {class: 'subreddit', text: s.title, href: '#'}));
  });
}

function humanFileSize(bytes, si) {
  var thresh = si ? 1000 : 1024;
  if(bytes < thresh) return bytes + ' B';
  var units = si ? ['kB','MB','GB','TB','PB','EB','ZB','YB'] : ['KiB','MiB','GiB','TiB','PiB','EiB','ZiB','YiB'];
  var u = -1;
  do {
    bytes /= thresh;
    ++u;
  } while(bytes >= thresh);
  return bytes.toFixed(1)+' '+units[u];
};

$(document).ready(function(){
  calendar = $('#mini-clndr').clndr({
    template: $('#calendar-template').html(),
    events: [],
    clickEvents: {
      click: function(target) {
        var $el = $(target.element);
        if(target.events.length) {
          var daysContainer = $('#mini-clndr').find('.days-container');
          daysContainer.toggleClass('show-events', true);
          $('#mini-clndr').find('.x-button').click( function() {
            daysContainer.toggleClass('show-events', false);
          });
        }
        if($el.hasClass('event')){
          var d = target.date._a;
          page = 1;
          end_reached = false;
          console.log(d[0] + ' ' + (d[1]+1) + ' ' + d[2]);
          load_data({date: d[0] + ' ' + (d[1]+1) + ' ' + d[2]})
        }
      }
    },
    numberOfRows: 6,
    adjacentDaysChangeMonth: true
  });

  $('#link').val('');
  page = 1;
  load_data();
  
  $(window).scroll(function(event){
    var curScroll = $('#content')[0].scrollTop;
    var maxScroll = $('#content')[0].scrollHeight - $('#content').height();
    if(curScroll == maxScroll && loading == false && end_reached == false) {
      loading = true;
      page += 1;
      $('#content').scrollTop = $('#content').scrollHeight - $('#content').height();
      load_data();
    }
    return false;
  });
  
  $('#submit').click(function(ev){
    $.ajax({
      url: "/job",
      type: 'post',
      dataType: 'json',
      data: JSON.stringify({link: $('#link').val(), only_first: $('#only-first').is(':checked'), with_images: $('#with-images').is(':checked')}),
      success: function(data){
        location.reload();
      },
      error: function(e){
        console.log('error');
      }
    });
  });
  
  $(".navbar-header a.navbar-btn").click(function(e) {
    var $btn = $(this);
    var i = $(this).attr('id');
    var menus = {'subreddits': '#cbp-spmenu-s1', 'dates': '#cbp-spmenu-s2', 'settings':  '#cbp-spmenu-s3'};
    var menuid = menus[i];
    var $menu = $(menuid);
    if($btn.hasClass('active')){
      $btn.removeClass('active');
      $menu.removeClass('cbp-spmenu-open');
    }else{
      $sibling = $('a.navbar-btn.active');
      $sibling.removeClass('active');
      $('.cbp-spmenu-open').removeClass('cbp-spmenu-open');
      $btn.addClass('active');
      $menu.addClass('cbp-spmenu-open');
    }
  });

  $('.subreddit').on('click', function(){
    //search({subreddit: $(this).text()});
    page = 1;
    end_reached = false;
    load_data({subreddit: $(this).text()});
  });
  
  $('.size').each(function(i, obj){
    var s = parseInt($(this).text());
    $(this).text(humanFileSize(s, false));
  });

  $('.closeq').click(function(){
    $('#queued').hide();
  });

  $('#submit-settings').click(function(){
    var o = {};
    if($('#set-email').val() != ''){
      o['email'] = $('#set-email').val();
    }
    if($('#set-password').val() != ''){
      o['password'] = $('#set-password').val();
    }
    $.ajax({
      url: "/u/update",
      type: 'post',
      dataType: 'json',
      data: JSON.stringify(o),
      success: function(data){
        $('#settings-text').html(
          '<div class="alert alert-'+data.type+'"><button class="close" type="button" data-dismiss="alert" aria-hidden="true">&times;</button><p>'+data.txt+'</p></div>'
        );
      },
      error: function(e){
        console.log('error');
      }
    });
  });

  $(document).on('click', 'a.delete-book', function(){
    var rid = $(this).parent().parent().attr('id');
    $.ajax({
      url: "/books/"+rid,
      type: 'delete',
      dataType: 'json',
      success: function(data){
        $('#'+rid).remove();
      },
      error: function(e){
        console.log('error');
      }
    });
  });

  //button.close type="button" data-dismiss="alert" aria-hidden="true" &times;
  //            p =msg[:txt]

  $('#options').click(function(){
    $('.submit-options').toggle('slow');
  });

  var currentMonth = moment().format('YYYY-MM');
  var nextMonth    = moment().add('month', 1).format('YYYY-MM');

  // there are a lot of options. the rabbit hole is deep.

          

});