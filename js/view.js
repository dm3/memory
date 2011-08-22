// tag list

// list of unique tags + all tag
var uniqueTags = _(data).chain().foldl(function(alltags, e) {
    if (e.tags) {
        return alltags.concat(e.tags.split(','));
    }
    return alltags;
}, []).uniq().value();
uniqueTags.push('all');
uniqueTags.push('untagged');

$('#header').append('<ul id="tags"></ul>');
var tagHolder = $('#tags');
_.each(uniqueTags, function(t) {
    tagHolder.append('<li id="' + t + '"><a href="#">'+ t +'</a></li>');
});

// events
$('#tags > li').not('li#all').click(function(e) {
    $tag = $(this);
    $tag.toggleClass('checked');
    if (!$tag.hasClass('checked')) {
        $('li#all').removeClass('checked');
    }

    updateLinks();
});

$('li#all').click(function(e) {
    $allTags = $('#tags > li');
    $tag = $(this);
    if ($tag.hasClass('checked')) {
        $allTags.removeClass('checked');
    } else {
        $allTags.addClass('checked');
    }

    updateLinks();
});

// hiding/showing links
function updateLinks() {
    var checkedTagNames = _($('#tags > li')).chain().filter(function(t) {
        return $(t).hasClass('checked');
    }).pluck('id').value();
    var linksToToggle = _.groupBy(data, function(link) {
        return _.any(checkedTagNames, function(tag) {
            return link.tags.indexOf(tag) != -1 || (link.tags == '' && tag == 'untagged');
        });
    });
    _.each(linksToToggle[true], function(link) {
        $('#' + link.hash).removeClass('hidden');
    });
    _.each(linksToToggle[false], function(link) {
        $('#' + link.hash).addClass('hidden');
    });
}

// init
$('#links > li > div').remove();
$('li#untagged').addClass('special');
$('li#all').addClass('special').click();
