package Scoop;
use strict;

use Time::HiRes qw(gettimeofday sleep);
use Compress::Zlib;

# ___________________________________________________________________________
#
# New comment display routines added by Hunter 03/10/08
# ___________________________________________________________________________

use constant {
	CACHE_OK			=>  1,	# operation succeeded
	ERR_CACHE_NOTFOUND	=>  0,	# the data doesn't exist
	ERR_CACHE_EXPIRED	=> -1,	# the data might exist, but is expired
	ERR_CACHE_CORRUPT	=> -2,	# the data exists, but doesn't match the expected serial
	ERR_CACHE_LOCKED	=> -3,	# the data is temporarily writelocked by another process
	
	ERR_CACHE_EXISTS	=> -4,	# something beat us to the write
	ERR_CACHE_WRITE		=> -5,	# a failure occurred upon writing the data
	ERR_CACHE_SERIAL	=> -6,	# a failure occurred upon writing the serial key
	ERR_CACHE_UNLOCK	=> -7,	# a failure occurred upon deleting the lock key
	
	ERR_CACHE_TOOBIG	=> -100,	# we can't store the value, because it exceeds the maximum possible slab size
	ERR_CACHE_OTHER		=> -9999,	# an unknown bad thing happened
};


sub comment_cache_fetch {
	my $S = shift;
	my $key = shift;
	my $serial = shift;
	
	$key = join ':', @$key if ref $key;		# handle "vectored" keys
	
	my $cache = $S->{MEMCACHED};
	my $key_lock		= 'lock_' . $key;
	my $key_serial		= 'serial_' . $key;
	my $lock_expires	= $S->{UI}->{VARS}->{ comment_cache_lock_duration	} || 0.5;
	my $serial_expires	= $S->{UI}->{VARS}->{ comment_cache_serial_duration	} || (12*60*60);
	my $retry_delay		= $S->{UI}->{VARS}->{ comment_cache_retry			} || 0;
	
	# If something's got the write lock, we can't read it yet. Since we can be reasonably sure
	# that we're going to be interested in whatever gets written, though, we can briefly wait for
	# the write to finish. Even if it takes n/10ths of a second, it's still a win if we can avoid
	# recalculating the requested value ourselves. Then check that we've got a cached serial
	# number, and that it's the one we wanted (or better).
	
	my($c_lock,$c_serial) = @{$cache->get_multi($key_lock,$key_serial)}{ $key_lock, $key_serial };
	
	if ($c_lock and $retry_delay) {
		Time::HiRes::sleep($retry_delay);
		($c_lock,$c_serial) = @{$cache->get_multi($key_lock,$key_serial)}{ $key_lock, $key_serial };
	}
	return (undef,ERR_CACHE_LOCKED ) if $c_lock;
	return (undef,ERR_CACHE_EXPIRED) unless ($c_serial and $c_serial >= $serial);
	
	# Otherwise, get the data. Note that we still have to be cautious that it's really there
	# and is the correct value, since it could have expired or (since we're not readlocking)
	# been overwritten. Hopefully our separate serial key will have caught nearly all "invalid
	# serial" situations, and we just have to check for unlikely and uncommon cases.
	
	my $data = $cache->get($key);
	   $data =~ s/^(\d+)://s;
	my $d_serial = $1;
	
	return (undef,ERR_CACHE_NOTFOUND) unless $d_serial;					# not found?
	return (undef,ERR_CACHE_CORRUPT) unless ($d_serial >= $serial);		# doesn't match expected serial?
	return ($data,CACHE_OK) if not $data;								# valid, but empty or zero?
###	return (Compress::Zlib::memGunzip($data),CACHE_OK);					# success; return it
	return ($data,CACHE_OK);											# success; return it
}


sub comment_cache_store {
	my $S = shift;
	my $key = shift;
	my $serial = shift;
	my $value = shift;
	
	$key = join ':', @$key if ref $key;		# handle "vectored" keys
	
	my $cache = $S->{MEMCACHED};
	my $key_lock		= 'lock_' . $key;
	my $key_serial		= 'serial_' . $key;
	my $lock_expires	= $S->{UI}->{VARS}->{ comment_cache_lock_duration	} || 0.2;
	my $serial_expires	= $S->{UI}->{VARS}->{ comment_cache_serial_duration	} || (12*60*60);
	my $expires			= $S->{UI}->{VARS}->{ comment_cache_duration		} || 120;
	
	# It may have been a while since we last fetched this data, so recheck the serial number. If
	# it's up to date, somebody beat us to the write. That's fine and helpful... _if_ the data
	# really still exists. We can check that by attempting an 'add' command on the data; if it
	# fails, we know the data is stil there. Note that we don't have to do this during our write
	# lock: since other writers write their data before they write the serial num, we can be
	# assured that if the key_serial is there and is up to date, the underlying data will either
	# be nonexistent (dumped from the cache for some reason) or up-to-date itself, barring some
	# hideous cache problem.
	
	my $c_serial = $cache->get($key_serial);
	if (($c_serial >= $serial) and not $cache->add($key,"0:",$lock_expires)) {
		$cache->delete($key_lock) or return ERR_CACHE_EXISTS;
		return CACHE_OK;
	}
	
	# Compress the data. This is necessary because comment threads can be very large: multiple
	# meg, uncompressed... even compressed, 0.5mb isn't uncommon. And we have a maximum slab size
	# of 1mb in memcached. Note that memGzip(), below, modifies the passed $value... that's only
	# ok here because we're passing the value by copy to this routine anyway.

# # (let Scoop do this automatically)
# 	my $cvalue = Compress::Zlib::memGzip($value);
# 		return ERR_CACHE_TOOBIG if (length $cvalue >= (1024*1024));		# still too big; abort
	
	# Try for the lock; if we can't get it, we can't write. Otherwise, write the data, then the
	# serial number, then finally release the lock. We do each write separately so that we can be
	# assured the sequence really happens in the proper order.
	
	$cache->add($key_lock,      $serial,   $lock_expires) or return ERR_CACHE_LOCKED;
	$cache->set($key, "$serial:$value",         $expires) or ($cache->delete($key_lock), return ERR_CACHE_WRITE);
	$cache->set($key_serial,    $serial, $serial_expires) or ($cache->delete($key_lock), return ERR_CACHE_SERIAL);
	$cache->delete($key_lock)							  or return ERR_CACHE_UNLOCK;
	return length $value;
}


#
# format_comments
#
# The main formatter for comments.  Rebuilt to more cleanly separate the various options and
# display parameters from the logic of the routine itself -- this should be a bit more flexible
# than the older code. It's also much faster.
#
# We want to avoid recursion here, because there's so much setup involved in this routine. Instead
# we create contextual stacks, and push/pop contexts from them. We expect the comments to be in a
# "flattened tree": an ordered list, children immediately after parents, with depth information
# attached, as returned by collect_comments.
#
#
sub format_comments {
	my $S = shift;
	my $p = shift;	# our context parameters
	
	my $sid = $p->{ sid };		# mandatory
	
	my $t_start = gettimeofday();

	# _____ find (generally static) site configuration settings

	my $SUI_vars   = $S->{UI}->{VARS};
	my $SUI_blocks = $S->{UI}->{BLOCKS};
	
	my $use_new		= $SUI_vars->{ show_new_comments } eq 'all';
	my $use_macros	= $SUI_vars->{ use_macros };
	my $use_mojo	= $SUI_vars->{ use_mojo   };
	my $rating_max  = $SUI_vars->{ rating_max };
	my $rating_min  = $SUI_vars->{ rating_min };
	my $hide_thresh = $SUI_vars->{ hide_comment_threshold } || $SUI_vars->{ rating_min };
	my $hide_rating = $SUI_vars->{ hide_rating_value };
	   $hide_rating = $rating_min-1 if ($hide_rating == '');
	my @rating_labels;	# We've moved to a simpler rating scheme: just use the first and last labels
	   @rating_labels = split /,/, $SUI_vars->{rating_labels} if ($SUI_vars->{rating_labels});
	my $rate_label = pop   @rating_labels;
	my $hide_label = shift @rating_labels || $hide_rating;
	
	my $use_cache = $SUI_vars->{ allow_comment_thread_caching };
	my $use_limit_rating_period = $SUI_vars->{ limit_comment_rating_period };
	my $use_limit_rating_hours	= $SUI_vars->{ limit_comment_rating_hours  };
	
	# _____ grab our calling parameters
	
	# These control the optional caching mechanism. We're frequently not able to fully cache the
	# results, and so must cache _intermediate_ results.  Given how expensive formatting large
	# threads can be, this is still a win -- and for users with few permissions, we can actually
	# manage to cache nearly everything.  Note that we assume the cache should be invalidated when
	# the number of comments in a thread changes, but we do _not_ invalidate the cache if ratings
	# change. Instead, we're willing to tolerate the ratings being out-of-date by $cache_duration
	# seconds, so long as any new ratings set by the user currently viewing the thread _are_
	# correctly shown. (Otherwise, users would be sorely confused upon page reloads, when their
	# ratings perhaps didn't show up.)
	
	my $cache				= $p->{ cache };					# currently unused; a cache object
	my $cache_as			= $p->{ cache_as };					# a cache name to use
	my $cache_duration		= $p->{ cache_duration } || $SUI_vars->{ comment_cache_duration } || 60;	# max duration of cached val, in seconds
	my $cache_triggered_at	= $p->{ cache_triggered_at } || 0;	# how many comments a thread should have before trying to cache it
	my $may_cache = ($use_cache and $cache_as);
	
	# things specific to the current page and params
	
	my $time_zone			= $p->{ time_zone		  };
	my $serial				= $p->{ serial			  };
	my $section				= $p->{ section			  };
	my $story_is_archival	= $p->{ story_is_archival };
	my $last_story_cid		= $p->{ last_story_cid	  };
	
	# The "display" parameters, defining how the comment thread should be formatted. Most of these
	# have reasonable defaults, but user and session prefs may change some; the caller is tasked
	# with passing us the right values.
	
	my $display_new			= $p->{ display_new		  };	# display whether each comment is "new" for this user
	my $display_replies 	= $p->{ display_replies	  };	# display the replies to each comment
	my $display_raters	 	= $p->{ display_raters	  };	# preload the lists of raters for each comment
	my $display_actions		= $p->{ display_actions	  };	# are we allowed to display "special" actions?
	my $display_threaded	= $p->{ display_threaded  };	# vs. flat
	my $display_full		= $p->{ display_full	  };	# render comment body and actions (vs. not calculating them)
	my $full_parent_paths	= $p->{ full_parent_paths };	# display full href to parent page, or just '#' ref?
	
	# The blocks to use for display.  These arrays define different blocks and delims for
	# different depths. Usually we specify only one or two depths: any depths reached that aren't
	# defined will use the delims of the last defined depth.  Note that these are not taken into
	# account when creating cache vectors, so if they can change independent of the passed display
	# parameters the cache won't update properly. We assume our caller only requests a cache if
	# they're explicitly passing us these only as invariant parameters.
	
	my $block				= $p->{ block	 };				# the normal comment block
	my $block_ed			= $p->{ block_ed };				# the block to use for editorial comments
	my $delim_level_start	= $p->{ delim_level_start };
	my $delim_level_end		= $p->{ delim_level_end	  };
	my $delim_item_start	= $p->{ delim_item_start  };
	my $delim_item_end		= $p->{ delim_item_end	  };

	my $n_blocks				= @$block;					# we need to know the max depth specified for each
	my $n_blocks_ed				= @$block_ed;
	my $n_delims_level_start	= @$delim_level_start;
	my $n_delims_level_end		= @$delim_level_end;
	my $n_delims_item_start		= @$delim_item_start;
	my $n_delims_item_end		= @$delim_item_end;
	
	# _____ find user permissions
	
	my $uid = $p->{ uid };
	my $user_anonymous = $p->{ user_anonymous };
	
	my $ratingchoice = $S->get_comment_option('ratingchoice');
	
	my $may_read = $S->have_section_perm('norm_read_comments', $section)
					or return '';
	
	my $may_new = ($use_new
					and $display_new
					and !$user_anonymous
					and !$story_is_archival);

	my $may_post = (!$user_anonymous
					and $S->have_section_perm('norm_post_comments', $section)
					and $S->have_perm('comment_post')
					and !$S->_check_archivestatus($sid));
	
	my $may_rate = ($use_mojo
					and !$user_anonymous
					and !$story_is_archival
					and $S->have_perm('comment_rate')
					and (!$ratingchoice || $ratingchoice eq 'yes')
					and $display_actions);
	
	my $may_hide = ($may_rate and ($S->{ TRUSTLEV } == 2 || $S->have_perm('super_mojo')));
	
	my $may_view_ratings			= ($ratingchoice ne 'hide');
	my $may_view_comments_editorial	= !$user_anonymous && $S->have_perm('editorial_comments');
	my $may_view_comments_hidden	= !$user_anonymous && $S->_may_view_hidden_comments;	# (1, 0, undef)
	my $maybe_view_comments_hidden	= !$user_anonymous && (!defined $may_view_comments_hidden);
	   $may_view_comments_hidden = 1 if $maybe_view_comments_hidden;
	
	my $may_view_comment_ip = (!$user_anonymous
								and $SUI_vars->{ view_ip_log    }
								and $SUI_vars->{ comment_ip_log }
								and $S->have_perm('view_comment_ip'));
	
	my $may_edit_user		= !$user_anonymous && $display_actions && $S->have_perm('edit_user');
	my $may_delete_comments = !$user_anonymous && $display_actions && $S->have_perm('comment_delete');
	my $may_remove_comments = !$user_anonymous && $display_actions && $S->have_perm('comment_remove');
	my $may_toggle_comments = !$user_anonymous && $display_actions && $S->have_perm('comment_toggle');
	
	# things unique to this particular user, and uncachable
	
	my $hide_disabled	= ($may_hide and !$S->trl_chk($uid));	# have we already used up all our hide ratings?
	my $last_cid_seen	= ($may_new and $S->story_highest_index($sid));
	my $current_ratings	= !$user_anonymous ? $S->_get_current_ratings($sid,$uid) : { };
	
	# ... and a few more things required for both cached and non-cached versions
	
	my($rate_type,$rate_hide_disabled,$action_admin,$action_parent);
	if ($display_full and $display_actions) {
		$rate_type			= $may_hide		 ? 'radio' : 'checkbox';
		$rate_hide_disabled	= $hide_disabled ? 'disabled="disabled" ' : '';
		$action_admin = join '',
							($may_delete_comments ? $SUI_blocks->{ comment_delete_link } : ()),
							($may_remove_comments ? $SUI_blocks->{ comment_remove_link } : ()),
							($may_toggle_comments ? $SUI_blocks->{ comment_toggle_link } : ());
		$action_parent = $full_parent_paths
							? qq| <a href="%%rootdir%%/comments/%%sid%%/%%pid%%#c%%pid%%">Parent</a> |
							: qq| <a href="#c%%pid%%">Parent</a> |;
	}
	
	# _____ attempt to obtain a partial result from the fragment cache
	
	# Note that we can't guess or assign a cache name based on our passed comments; we must be
	# assigned one.  It makes the most sense to pass sid or story_id as the cache_as, _if_ we're
	# trying to cache an entire story thread. There may be other threads worth caching, as well;
	# leave it to the caller to decide.
	
	my $cache_vector;
	my $found_cached;
	my $r;
	
	if ($may_cache) {
		# Assign ourselves a normalized node name based on all display elements and prefs that
		# could alter the cached result. Aside from the annoyance of having to do it, this isn't
		# as bad as it looks: since most users will have the same sets of preferences and
		# permissions, the total number of cache nodes used in practice will be small.
		
		$cache_vector = $p->{ cache_vector } = $cache_as . ':' . join '', map { $_ ? '1' : '0' } (
			$display_new,			$display_replies,		$display_raters,
			$display_actions,		$display_full,			$display_threaded,
			$full_parent_paths,
			$may_new,		$may_post,		$may_rate,		$may_hide,
			$may_view_ratings,
			$may_view_comments_hidden,		$maybe_view_comments_hidden,
			$may_view_comments_editorial,	$may_view_comment_ip,
			$may_edit_user,		$may_delete_comments,		$may_toggle_comments,
		);
		
		# Attempt to get the desired version of the desired vector from the cache.
		#
		# Note that we can't make the "true" serial part of the vector, because it updates with
		# every recommend... instead, we have to make an artificial serial number, which is just
		# the number of comments currently in the story.
		#
		# We're going to ditch the cached data if a comment gets made in the thread, but is it
		# possible to do almost the same trick that we do with ratings? Use what's already cached
		# and just build from it?  Hmm... maybe, but that's even trickier. We'll leave that as a
		# TODO.
		
		my $t_start = gettimeofday();
		my $err;
		($r,$err) = $S->comment_cache_fetch($cache_vector,$last_story_cid);
		my $t_end = gettimeofday();
		$p->{ t_cache_fetch } = sprintf("%.03f", $t_end-$t_start) . " [$last_story_cid] --> $err";
		
		$found_cached = length $r;
	}
	
	my $t_end = gettimeofday();
	$p->{ t_init_format } = sprintf("%.03f", $t_end-$t_start);
	
	# _____ obtain the comment list from the collector and format the results... but only if we need to
	
	my $comments_list;
	unless ($found_cached) {
	
		# call the collector method, obtaining our "raw" comments list from the database or cache
		
		$comments_list = $S->collect_comments($p);
		
		### BUG: it would sometimes be desirable for a post_collector_method to actually _change_
		### our context parameters in response to the collected comments, possibly altering the
		### display from full to something else, or disabling further posting, etc. What the heck
		### do we do then? I *think* the most sensible thing to do would be to call ourselves, but
		### with the collector callbacks nullified such that we're only operating on our modified
		### context and the now-already-generated collected comments.  We'd likely need the
		### collector to set a flag marking when and if we need to do that... or we need a
		### workflow manager that's reponsible for calling both routines.  That's too much work,
		### so for now we'll just ignore the issue.
	}

	my $t_start = gettimeofday();
		
	unless ($found_cached) {
		# begin loop
		
		my $i = 0;
		my $n_comments = $p->{ n_collected } = @$comments_list;
		my $old_depth = -1;
		my @end_delim_level_stack;
		my @end_delim_item_stack;
		my @raters_stack;
		my @comments_text;
		
		my $rating_format = $may_view_ratings
			? $display_full
				? $SUI_blocks->{ rating_format }
				: $SUI_blocks->{ rating_format_shrink }
			: '';
		
	# 	use Data::Dumper;
	# 	my $pp = &Data::Dumper::Dumper($p);
	# 	   $pp =~ s/</&lt;/g;
	# 	   $pp =~ s/>/&gt;/g;
	# 	push @comments_text, join '',
	# 		"\n<blockquote><code><pre>",
	# 		"params: ", (map { "<br/>$_ => $p->{$_}, " } sort keys %$p),
	# 		"<br /><hr />",
	# 		"n_comments: ", (scalar @$comments_list),
	# 		"<br />", join("<br />",
	# 		"rating_min:$rating_min",
	# 		"rating_max:$rating_max",
	# 		"may_new:$may_new",
	# 		"may_read:$may_read",
	# 		"may_post:$may_post",
	# 		"may_rate:$may_rate",
	# 		"may_hide:$may_hide",
	# 		"may_hide_disabled:$may_hide_disabled",
	# 		"may_view_ratings:$may_view_ratings",
	# 		"may_view_comments_hidden:$may_view_comments_hidden",
	# 		"may_view_comments_editorial:$may_view_comments_editorial",
	# 		"may_view_comment_ip:$may_view_comment_ip",
	# 		"may_edit_user:$may_edit_user",
	# 		"may_delete_comments:$may_delete_comments",
	# 		"may_remove_comments:$may_remove_comments",
	# 		"may_toggle_comments:$may_toggle_comments",
	# 		),
	# 		"</pre></code></blockquote>\n\n";
		
		while (1) {
			my $comment = $comments_list->[ $i ] or last;
			my $cid		= $comment->[ IX_COMMENT_cid   ];
			my $depth	= $comment->[ IX_COMMENT_depth ];
			
			# If this comment is not visible to the user, skip it and every comment beneath it that's
			# deeper than it is. The cached version is a bit tricky, because we don't necessarily know
			# which hidden comments should really _be_ "hidden", in the particular case of users that
			# elect to only hide comments they've personally trollrated.
			
			my $comment_is_editorial = $comment->[ IX_COMMENT_pending ];
			my $comment_is_hidden = ( $use_mojo
				&& ($comment->[ IX_COMMENT_points ] ne 'none')
				&& ($comment->[ IX_COMMENT_points ] < $hide_thresh)
			);
			if (($comment_is_hidden && !$may_view_comments_hidden)
					or ($comment_is_editorial && !$may_view_comments_editorial)) {
				1 while (++$i and ($i < $n_comments and $comments_list->[$i][ IX_COMMENT_depth ] > $depth));
				next;
			}
			my $hide_item = 0;
			if ($comment_is_hidden and $maybe_view_comments_hidden) {
				if ($may_cache) {
					# We actually have to *wrap* this comment and all children in a special set of
					# delimiters, so that it can be optionally hidden by the cache thaw. We'll do this
					# via a delimiter stack, just like the other delimiters.
					$hide_item = 1;
				} elsif (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $hide_rating) {
					# otherwise we only hide it if we've trollrated it.
					1 while (++$i and ($i < $n_comments and $comments_list->[$i][ IX_COMMENT_depth ] > $depth));
					next;
				}
			}
			
			# Otherwise, we're displaying it.

			# If the depth has changed from last comment to this, determine which level delimiters
			# we should use, and which delimiters from the stack need to be pushed back out now.
			# If the depth hasn't changed, we know we can just push the last item delim. Note that
			# starting delims are added directly to the block, below, while end delimiters are
			# pushed to a stack. This allows starting delims to be parsed for comment-specific
			# macros.

			### TODO: to parse end delims, how would we keep track of the "parent" comment of a
			### level? we'd either have to parse it *first*, before it was put on the stack, or
			### make the comment an object that could be passed (such that all known macros could
			### still be used and valid.)
			
			my $delim_start_level = '';
			if ($depth == $old_depth) {						# staying at the same level?
				push @comments_text, pop @end_delim_item_stack;
			} elsif ($depth < $old_depth) {					# ending an old level?
				my $d = $depth;								# pop the stored info until
				push @comments_text,						# we've re-reached the proper depth
					pop(@end_delim_item_stack),
					pop(@end_delim_level_stack) while ($d++ < $old_depth);
				push @comments_text, pop @end_delim_item_stack;
			} else {										# starting a new level?
				$delim_start_level		   = (($n_delims_level_start && $delim_level_start->[ $depth < $n_delims_level_start ? $depth : $n_delims_level_start-1 ]) || '');
				push @end_delim_level_stack, (($n_delims_level_end   && $delim_level_end->[   $depth < $n_delims_level_end   ? $depth : $n_delims_level_end-1   ]) || '');
			}
			
			# Set up the item delimiters for this item, optionally including any necessary "HIDE"
			# macros for our cache thawer.
			
			my $delim_start_item	  = ($hide_item ? "%%HIDE:$cid%%" : '')
									  . (($n_delims_item_start && $delim_item_start->[ $depth < $n_delims_item_start ? $depth : $n_delims_item_start-1 ]) || '');
			push @end_delim_item_stack, (($n_delims_item_end   && $delim_item_end->[   $depth < $n_delims_item_end   ? $depth : $n_delims_item_end-1   ]) || '')
									  . ($hide_item ? "%%/HIDE:$cid%%" : '');
			
			# Determine which UI block should be used.
			
			my $b = $delim_start_level
				  . $delim_start_item
				  . ($comment_is_editorial			# is it an editorial comment, or a normal one?
						? $block_ed->[	$depth < $n_blocks_ed ? $depth : $n_blocks_ed-1	]
						: $block->[		$depth < $n_blocks	  ? $depth : $n_blocks-1	] );
			
			# calculate all the interpolatable data.
			#
			# In an ideal world, dang it, we'd know which of these things we needed BEFORE we
			# calculated them, so we didn't waste time on unused things.  But is it worth it?
			# We'll at least do them in two "layers", full and not full, so that we can skip
			# body, sig and action stuff if we're not displaying them.
			
			my $pid		= $comment->[ IX_COMMENT_pid ];
			my $aid		= $comment->[ IX_COMMENT_uid ];
			my $points	= $comment->[ IX_COMMENT_points ];
			my $subject	= $comment->[ IX_COMMENT_subject ];
			
			my $author		= $S->user_data($aid);
			my $author_anon = $aid < 0;
			my $author_nick = $author->{ nickname };		# $S->get_nick_from_uid($aid);
			
			my $editorial	= $comment_is_editorial ? 'Editorial: ' : '';
			my $member		= $SUI_blocks->{"mark_$author->{perm_group}"};
			
			my $new = $may_new
				? $may_cache
					? "%%NEW:$cid:$aid%%"					# let the cache thaw deal with it
					: ($last_cid_seen < $cid and $uid != $aid)
						? $SUI_blocks->{ new_comment_marker }
						: ''
				: '';
			
			# calculate the ratings info
			#
			# $points and $numrate are hacks: in the older Scoop blocks we still use %%score%% and
			# %%num_ratings%% everywhere, so we just fake them to instead display the newer-style
			# "positive" and "negative" ratings.
			#
			# It may frequently be preferred to avoid loading the ratings, leaving it to AJAX
			# calls to load them if needed. In addition to greatly speeding up formatting on large
			# pages, it simplifies caching immensely.
			#
			# Caching note: people don't necessarily need to see how other people rated a comment
			# right away, but they _do_ want to make sure that their _own_ ratings are immediately
			# visible if they reload the page. We therefore have to only partially cache the
			# rating lists and scores, so that we can tweak them per-user for any users that have
			# ratings abilities.
			
			my($recommend_list,$points,$numrate,$n_ratings_pos,$n_ratings_neg);
			if ($may_view_ratings) {
				if (defined $comment->[ IX_COMMENT_raters ]) {
					# this is pretty expensive... maybe there's another way?
					my $raters = Storable::thaw(MIME::Base64::decode($comment->[ IX_COMMENT_raters ]));
					
					if ($may_cache && $may_rate) {
						push @raters_stack, map { join('|', $cid, $_->{rating}, $_->{uid}, $_->{nick}) } @$raters;
						$recommend_list = "%%RATING_LIST:$cid%%";		# let the cache thaw deal with it
					} else {
						my $raters_pos = join ", ", map { qq|<a href="/user/uid:$_->{uid}">$_->{nick}</a>| } grep { $_->{ rating } == $rating_max  } @$raters;
						my $raters_neg = join ", ", map { qq|<a href="/user/uid:$_->{uid}">$_->{nick}</a>| } grep { $_->{ rating } == $hide_rating } @$raters;
						if ($raters_pos or $raters_neg) {
							my $block_pos = $raters_pos ? $SUI_blocks->{ recommend_raters } : '';
							   $block_pos =~ s/%%recraters%%/$raters_pos/ if $block_pos;
							my $block_neg = $raters_neg ? $SUI_blocks->{ troll_raters } : '';
							   $block_neg =~ s/%%trollraters%%/$raters_neg/ if $block_neg;
							
							$recommend_list = $SUI_blocks->{ rating_list };
							$recommend_list =~ s/__RECRATE__/$block_pos/;
							$recommend_list =~ s/__TROLLRATE__/$block_neg/;
						}
					}
				}
				if (defined $comment->[ IX_COMMENT_recrate ]) {
					if ($may_cache && $may_rate) {
						$points  = $n_ratings_pos = "%%NRATEPOS:${cid}%%+";		# let the cache thaw deal with it
						$numrate = $n_ratings_neg = "%%NRATENEG:${cid}%%-";
					} else {
						$points  = $n_ratings_pos = $comment->[ IX_COMMENT_recrate   ] . '+';
						$numrate = $n_ratings_neg = $comment->[ IX_COMMENT_trollrate ] . '-';
					}
				} else {
					$points  = $comment->[ IX_COMMENT_points  ];	# obsolete, but still might be used here and there
					$numrate = $comment->[ IX_COMMENT_numrate ];
				}
			}
			
			# Calc these only if we're in "full" mode, such that we'll need them:
			
			my($body,$sig,$action,$action_edit,$action_ip,$toggle,$email,$url);
			if ($display_full) {
				# the main comment body...
				
				$body = $comment->[ IX_COMMENT_comment ];
				$body &&= $S->process_macros($body,'comment') if $use_macros;
				
				# signature behavior... (sig_status is probably obsolete at this point(?), but
				# we'll run through the motions anyway)
				
				$sig = $author->{prefs}{sig} || '';
				$sig &&= ($comment->[ IX_COMMENT_sig_status ] == 1)
							? qq|<p class="sig">$author->{prefs}->{sig}</p>|
							: ($comment->[ IX_COMMENT_sig_status ] == 0)
								? $comment->[ IX_COMMENT_sig ]
								: '';
				$sig &&= $S->process_macros($sig,'pref') if $use_macros;
				
				if ($display_actions) {
					my $action_rate;									# the ratings form...
					if ($may_rate
							and (!$use_limit_rating_period
							  or ($use_limit_rating_period
									&& ($use_limit_rating_hours > $comment->[ IX_COMMENT_hoursposted ])))) {
						if ($may_cache) {
						   $action_rate = "%%RATEFORM:$cid:$aid%%";		# let the cache thaw deal with it
						} elsif ($uid != $aid) {
							my $rec_rated  = (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $rating_max ) ? 'checked="checked"' : '';
							my $hide_rated = (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $hide_rating) ? 'checked="checked"' : '';
							
							$action_rate  = qq|<input type="$rate_type" id="rc$cid" name="r$cid" value="$rating_max" $rec_rated\/><label for="rc$cid">$rate_label<\/label>|;
							$action_rate .= qq|<input type="radio" id="t$cid" name="r$cid" value="$hide_rating" $hide_rated $rate_hide_disabled\/><label for="t$cid">$hide_label<\/label>|
								if $may_hide;
							$action_rate .= qq|<input type="submit" class="rab" name="rate" value="Rate All" \/>|;
						}
					}
					
					$action = join ' | ',
						($pid ? $action_parent : ()),
						($may_post ? qq| <a href="%%rootdir%%/comments/%%sid%%/%%cid%%/post#here">Reply to This</a> | : ()),
						($action_rate || ());
					$action &&= "[ $action ] ";
					$action .= $action_admin;
					
					# other action links...
					
					$action_edit = (!$author_anon && $may_edit_user) ? qq| [<a href="%%rootdir%%/user/| . $S->urlify($author_nick) . qq|/edit">Edit User</a>] | : '';
					$action_ip	 = $may_view_comment_ip ? qq| <a href="/iplookup/$comment->[IX_COMMENT_commentip]">*</a> | : '';
					$toggle		 = $comment_is_editorial ? 'toggle_normal' : 'toggle_editorial';
				}
				
				# a few more misc possible interpolations...
				
				my $author_email = $author->{ fakeemail };
				my $author_url	 = $author->{ homepage };
				$email = $author_email ? qq|(<a href="mailto:$author_email">$author_email<\/a>)| : '';
				$url   = $author_url   ? qq|<a href="$author_url">$author_url<\/a>| : '';
			}
			
			# Now, finally, put it all together.
			#
			# We can either put the known tags in a hash, or do them sequentially. Tough call.
			# We'll do them sequentially for now so that we have a good speed comparision w/ the
			# older code for the rest of it... we can test alternatives later.
			#
			# (a cursory test, partial code below, seems to indicate that a hash of known tags is
			# pretty much the same speed as doing them sequentially.)
			
	# 		my %known_tags_full = (
	# 			pid		=> $pid,
	# 			... etc ...
	# 		);
	#		my $taglist = $display_full ? \%known_tags_full : \%known_tags_minimal
	# 		$b =~ s/(%%(\w+)%%)/
	# 			exists $taglist->{ $2 }
	# 				? $taglist->{ $2 }
	# 				: $1;
	# 		/eg;
	
			$b =~ s/%%new%%/$new/g;
			$b =~ s/%%rating_format%%/$rating_format/g;
			$b =~ s/%%recommend_list%%/$recommend_list/g;
			$b =~ s/%%num_ratings%%/$numrate/g;
			$b =~ s/%%score%%/$points/g;
		#	$b =~ s/%%n_raters_pos%%/$n_raters_pos/;
		#	$b =~ s/%%n_raters_neg%%/$n_raters_neg/;
			
			if ($display_full) {
				$b =~ s/%%actions%%/$action/g;
				$b =~ s/%%edit_user%%/$action_edit/g;
				$b =~ s/%%comment_ip%%/$action_ip/g;
				$b =~ s/%%toggle%%/$toggle/g;
				$b =~ s/%%comment%%/$body/g;
				$b =~ s/%%sig%%/$sig/g;
				$b =~ s/%%email%%/$email/g;
				$b =~ s/%%url%%/$url/g;
			} else {
				# HACK: fix a nasty recursive bug, since "comment" is frequently the name of our own block!
				$b =~ s/%%comment%%//g;
			}
	
			$b =~ s/%%editorial%%/$editorial/g;
			$b =~ s/%%member%%/$member/g;
			$b =~ s/%%mini_date%%/$comment->[ IX_COMMENT_mini_date ]/g;
			$b =~ s/%%date%%/$comment->[ IX_COMMENT_f_date ]/g;
			$b =~ s/%%subject%%/$subject/g;
			$b =~ s/%%name%%/$author_nick/g;
			
		#	$b =~ s/%%rootdir%%/$rootdir/g;		# done elsewhere
			$b =~ s/%%sid%%/$sid/g;
			$b =~ s/%%cid%%/$cid/g;
			$b =~ s/%%pid%%/$pid/g;
			$b =~ s/%%uid%%/$aid/g;
			
			# Push the finished comment to the pile. Note that we may yet still have replies to
			# write, and note also that we may be "closing" several levels of depth besides our
			# own, in the case of nested comments. That'll be done on the next loop iteration.
			
			push @comments_text, $b;
			$old_depth = $depth;
			
			# should we skip replies to this comment?
			# if so, increment our iterator until we get the first thing that's not a reply.
			
			unless ($display_replies) {
				1 while (++$i and ($i < $n_comments and $comments_list->[$i][ IX_COMMENT_depth ] > $depth));
				next;
			}
			
			# All done; do the next comment
			
			$i++;
		}
		
		# _____ end loop: pop out any leftover delimiters
		
		while (@end_delim_item_stack) {
			push @comments_text,
				pop(@end_delim_item_stack),
				pop(@end_delim_level_stack);
			$old_depth--;
		}
		
		$r = join '', @comments_text;
		
		# _____ cache the results in the fragment cache
		
		if ($may_cache) {
			my $raters_stack  = join "\n", @raters_stack;
			my $thread_ratings = "%%THREADRATINGS%%${raters_stack}%%/THREADRATINGS%%";
			
			# I hate to do this this way, but we want to keep the ratings with the thread, in
			# memcached, because I'm not sure what the consequences would be if they got out of
			# sync. Worth thinking about, though -- pushing and pulling this off of a 2-megabyte
			# return value certainly has some overhead.
			
			$r = $thread_ratings . $r;
			
			# store it in the cache

			my $t_start = gettimeofday();
			my $ok = $S->comment_cache_store($cache_vector,$last_story_cid,$r);
			my $t_end = gettimeofday();
			
			$p->{ t_cache_store } = sprintf("%.03f", $t_end-$t_start) . " [STATUS/SIZE:$ok]";
		}
	}
	my $t_end = gettimeofday();
	$p->{ t_formatted } = sprintf("%.03f", $t_end-$t_start);
	
	my $t_start = gettimeofday();
	
	# _____ interpolate any remaining fragment cache stuff
	
	# Note that these are all (nearly) identical to the same code, above, that handle the
	# non-cached cases. Sadly, unless we can figure out how to merge the two without sacrificing
	# speed in the non-cached cases, it means we have to manually take care to keep the two
	# versions in sync.  Perhaps we make them closures in the current context, thus able to see
	# all the required vars but w/ subroutine calling conventions?  A little slower, but might be
	# worth it to keep things better together?
	
	if ($may_cache) {
	
		# first get the packed ratings we cached along with the story
		
		my @ratings_pos;
		my @ratings_neg;
		if ($may_rate) {
			$ratings_pos[ $last_story_cid ] = undef;  # preset array sizes for better speed
			$ratings_neg[ $last_story_cid ] = undef;
			$r =~ s/%%THREADRATINGS%%(.*?)%%\/THREADRATINGS%%//s;
			foreach (map { [ split /\|/ ] } split /\n/s, $1) {
				$_->[1]	? $ratings_pos[ $_->[0] ]{ $_->[ 2 ] } = $_->[ 3 ]
						: $ratings_neg[ $_->[0] ]{ $_->[ 2 ] } = $_->[ 3 ];
			}
		}
		
		# strip comments hidden for this particular user
		
		$r =~ s/%%HIDE:(\d+)%%(.*?)%%HIDE:(\1)%%/
				my($cid,$r) = ($1,$2);
				(exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $hide_rating)
					? ''
					: $r
			/eg if $maybe_view_comments_hidden;
		
		# determine which things should get a "new" marker
		
		$r =~ s/%%NEW:(\d+):(\d+)%%/
				my($cid,$aid) = ($1,$2);
				($last_cid_seen < $cid and $uid != $aid)
					? $SUI_blocks->{ new_comment_marker }
					: ''
			/eg if $may_new;
		
		# these are only done if the user can currently rate comments. If they can't, they were
		# given a cache vector in which these macros don't exist anyway, because we were smart
		# enough to know the results could be prebuilt.
		
		if ($may_rate) {
			# put the rating form on any comment _not_ authored by the current user
			
			$r =~ s/%%RATEFORM:(\d+):(\d+)%%/
					my($cid,$aid) = ($1,$2);
					my $rr;
					if ($uid != $aid) {
						my $rec_rated  = (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $rating_max ) ? 'checked="checked"' : '';
						my $hide_rated = (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $hide_rating) ? 'checked="checked"' : '';
						
						$rr  = qq|<input type="$rate_type" id="rc$cid" name="r$cid" value="$rating_max" $rec_rated\/><label for="rc$cid">$rate_label<\/label>|;
						$rr .= qq|<input type="radio" id="t$cid" name="r$cid" value="$hide_rating" $hide_rated $rate_hide_disabled\/><label for="t$cid">$hide_label<\/label>|
							if $may_hide;
						$rr .= qq|<input type="submit" class="rab" name="rate" value="Rate All" \/>|;
					} else {
						$rr = '';
					}
					$rr;
				/eg;
			
			# Build the updated ratings lists. This is tricky, to say the least: we've got to find
			# out whether the user rated each comment at the time it was cached, and whether
			# they've changed their ratings since then. That's the only way to update our cached
			# page to ensure we're always showing them their most recent ratings.
			
			my $nick = $S->get_nick_from_uid($uid);
			
			$r =~ s^%%RATING_LIST:(\d+)%%^
					my $cid = $1;
					my $cratings_pos = $ratings_pos[$cid];
					my $cratings_neg = $ratings_neg[$cid];
					my $user_rated_pos		= exists $cratings_pos->{ $uid };
					my $user_rated_neg		= exists $cratings_neg->{ $uid };
					my $user_now_rated_pos	= (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $rating_max );
					my $user_now_rated_neg	= (exists $current_ratings->{ $cid } and $current_ratings->{ $cid } == $hide_rating);
					$cratings_pos->{ $uid } = $nick if ($user_now_rated_pos && !$user_rated_pos);
					$cratings_neg->{ $uid } = $nick if ($user_now_rated_neg && !$user_rated_neg);
					delete $cratings_pos->{ $uid }  if ($user_rated_pos && !$user_now_rated_pos);
					delete $cratings_neg->{ $uid }  if ($user_rated_neg && !$user_now_rated_neg);
					
					my $raters_pos = join ", ", map { qq|<a href="/user/uid:$_">$cratings_pos->{$_}</a>| } sort { $a <=> $b } keys %{$cratings_pos};
					my $raters_neg = join ", ", map { qq|<a href="/user/uid:$_">$cratings_neg->{$_}</a>| } sort { $a <=> $b } keys %{$cratings_neg};
					
					my $recommend_list;
					if ($raters_pos or $raters_neg) {
						my $block_pos = $raters_pos ? $SUI_blocks->{ recommend_raters } : '';
						   $block_pos =~ s/%%recraters%%/$raters_pos/ if $block_pos;
						my $block_neg = $raters_neg ? $SUI_blocks->{ troll_raters } : '';
						   $block_neg =~ s/%%trollraters%%/$raters_neg/ if $block_neg;
						
						$recommend_list = $SUI_blocks->{ rating_list };
						$recommend_list =~ s/__RECRATE__/$block_pos/;
						$recommend_list =~ s/__TROLLRATE__/$block_neg/;
					}
					$recommend_list;
				^eg;
			
			# Now we can (finally) update the ratings numbers as well.
			
			$r =~ s/%%NRATEPOS:(\d+)%%/ scalar(keys %{$ratings_pos[ $1 ] || {}}) /eg;
			$r =~ s/%%NRATENEG:(\d+)%%/ scalar(keys %{$ratings_neg[ $1 ] || {}}) /eg;
		}
	}

	# finally, we can return the results
	
	my $t_end = gettimeofday();
	$p->{ t_post_format } = sprintf("%.03f", $t_end-$t_start);

	$r;
}


# ___________________________________________________________________________
#
# END new routines -- Hunter 03/10/08
#
# ___________________________________________________________________________


sub format_comment {
	my $S = shift;
	my $comment = shift; # HASHREF^W ARRAYREF
	
	my $sid = $comment->[0];
	my $cid = $comment->[1];
	my $pid = $comment->[2];
	my $aid = $comment->[8];

	# If we're passed $params by our caller, use it. Otherwise seed it ourselves,
	# and pass it to our children to keep them from recalculating the same things.
	# Note that format_comment requires a *lot* more setting up than most other routines,
	# so we leave a marker in the $params to note whether we've set up our own fields,
	# and set them up seperately the first time we're called.
	# In the cache, we'll put anything that's difficult to calculate, is frequently
	# used, and that doesn't ever change within a particular request and story.
	
	$S->{COMPARAM} ||= {					# the four usual params that we can always expect
			check_archivestatus		=> $S->_check_archivestatus($sid),
			story_highest_index		=> $S->story_highest_index($sid),
			may_view_hidden_comments=> $S->_may_view_hidden_comments,
			dispmode				=> $S->get_comment_option('commentmode'),
	};
	unless ($S->{COMPARAM}->{ _init_format_comment }) {
		my $section = $S->_get_story_section($sid);
		$S->{COMPARAM}->{ _init_format_comment } = 1;          # mark that we've inited the params
		$S->{COMPARAM}->{ section              } = $section;
		$S->{COMPARAM}->{ may_read_comments    } = $S->have_section_perm('norm_read_comments', $section);
		$S->{COMPARAM}->{ sect_perm_post       } = $S->have_section_perm('norm_post_comments', $section);
		$S->{COMPARAM}->{ may_comment_post     } = $S->have_perm('comment_post');
		$S->{COMPARAM}->{ view_comment_ip      } = $S->have_perm('view_comment_ip');   
		$S->{COMPARAM}->{ comment_delete       } = $S->have_perm('comment_delete');
		$S->{COMPARAM}->{ comment_remove       } = $S->have_perm('comment_remove');
		$S->{COMPARAM}->{ comment_toggle       } = $S->have_perm('comment_toggle');
		$S->{COMPARAM}->{ check_commentstatus  } = $S->_check_commentstatus($sid);     # 1 = read only
	}
	my $may_read_comments	= $S->{COMPARAM}->{ may_read_comments }	or return '';
	my $check_archivestatus = $S->{COMPARAM}->{ check_archivestatus };
	my $story_highest_index = $S->{COMPARAM}->{ story_highest_index };
	my $section				= $S->{COMPARAM}->{ section };
	my $check_commentstatus	= $S->{COMPARAM}->{ check_commentstatus };
	my $sect_perm_post		= $S->{COMPARAM}->{ sect_perm_post };
	my $may_comment_post	= $S->{COMPARAM}->{ may_comment_post };
	my $view_comment_ip		= $S->{COMPARAM}->{ view_comment_ip };
	my $comment_delete		= $S->{COMPARAM}->{ comment_delete };
	my $comment_remove		= $S->{COMPARAM}->{ comment_remove };
	my $comment_toggle		= $S->{COMPARAM}->{ comment_toggle };
	my $dispmode			= $S->{COMPARAM}->{ dispmode };

	# return nothing unless they have permission to read the comments
	#unless ( ($S->_does_poll_exist( $sid ) && $S->have_perm('poll_read_comments') ) ||
	# return unless $may_read_comments;	# we already do this above

	#if ( !$S->have_perm('editorial_comments') && $comment->[12] ) {
	#	return '';
	#} 

	#$sect_perm_post = 1 if ($S->_does_poll_exist($sid) && $S->have_perm('poll_post_comments'));

###	my $cgi_sid = $S->{CGI}->param('sid');	# unused
	my $cgi_cid = $S->{CGI}->param('cid');
	my $cgi_pid = $S->{CGI}->param('pid');
	my $cgi_tool= $S->{CGI}->param('tool');
	my $op		= $S->{CGI}->param('op');
	my $detail	= $S->{CGI}->param('detail');
	my $dynamic = ($op eq 'dynamic');
	
	my $dm = $S->{CGI}->param('commentDisplayMode')
				|| (($S->{UID} > 0) ? $S->pref('commentDisplayMode') : $S->session('commentDisplayMode'));
	my $is_shrink_mode = ($dm eq 'shrink');
	if ($op eq 'update') {
		$is_shrink_mode = ($detail eq 's');
	} elsif ($op eq 'comments') {
		$is_shrink_mode = 0;
	} elsif ($op eq 'displaystory' && $detail eq 'f') {
		$is_shrink_mode = 0;
	}
	
	# Only build the delimiter list for this mode and level if nothing else has already built it.
	# otherwise, we'll be redoing this all over again for every subthread, which is
	# pretty inefficient.  Note that "depth" is always zero, here.
	
	my($start, $end, $level_start, $level_end, $item_start, $item_end) =
		@{ $S->{COMPARAM}->{ delimiters }{ $dispmode }[ 0 ]
			||= [ $S->_get_comment_list_delimiters($sid, $dispmode, 0) ] };
	
	my $user = $S->user_data($aid);
	
	my $alone_mode	 = ($comment->[$#{$comment}] eq 'alone');
	my $preview_mode = ($comment->[$#{$comment}] eq 'Preview');
	my $posting_comment = ($op eq 'comments' && $cgi_tool eq 'post') ? 1 : 0 ;	
	
	my $replies;
	   $replies = (($S->get_list($sid, $cid, undef, undef))[0] || '')
			if (!$alone_mode && !$preview_mode);
	
	#if (($dynamic || $dispmode eq 'dthreaded' || $dispmode eq 'dminimal')  && !$preview_mode) {
		# Add a button to collapse this comment, and expand/collapse
		# its subthread
	#	my $minus = $S->{UI}->{BLOCKS}->{dynamic_collapse_bottom_link} || '-';
	#	my $pplus = $S->{UI}->{BLOCKS}->{dynamic_expand_thread_link} || '++';
	#	my $mminus = $S->{UI}->{BLOCKS}->{dynamic_collapse_thread_link} || '--';
	#	$comm_options .= qq|
	#		<TT><A STYLE="text-decoration:none" HREF="javascript:void(toggle($cid,1))">$minus</A></TT> \|
	#		<TT><A STYLE="text-decoration:none" HREF="javascript:void(toggleList(replies[$cid],0))">$mminus</A></TT>
	#		<TT><A STYLE="text-decoration:none" HREF="javascript:void(toggleList(replies[$cid],1))">$pplus</A></TT> \||;
	#}

	my $comm_options;
	if ($pid != 0) {
		my $opstring = 'comments';
		my $parent_link = ($dispmode eq 'flat_unthread' || $op ne 'comments') ?
						  "#c$pid" :
						  "%%rootdir%%/$opstring/$sid/$pid#c$pid";

		$comm_options .= qq| <a href="$parent_link">Parent</a> |;
		#warn "Comments/Format.pm: Reply to this ".$sid;
		if (!$preview_mode && $may_comment_post && !$posting_comment && !$check_commentstatus && $sect_perm_post && !$check_archivestatus ) {
			$comm_options .= qq|\| <a href="%%rootdir%%/comments/$sid/$cid/post#here">Reply to This</a> |;
		}

	} else {
		#warn "Comments/Format.pm: Reply to this ".$sid;
		if (!$preview_mode && $may_comment_post && !$posting_comment && !$check_commentstatus && $sect_perm_post && !$check_archivestatus ) {
			$comm_options .= qq| <a href="%%rootdir%%/comments/$sid/$cid/post#here">Reply to This</a> |;
		}
	}
	
	my $rate = $S->get_comment_option('ratingchoice');
	if ((!$rate || $rate eq 'yes') && ($S->{UID} != $aid) && !$check_archivestatus) {
		my $curr_rating = $S->_get_current_rating($sid, $cid, $S->{UID});
		my $rate_form;
		if ($S->{UI}->{VARS}->{limit_comment_rating_period}) {
		    $rate_form = $S->_rating_form($curr_rating, $cid)
				if ($comment->[5] < $S->{UI}->{VARS}->{limit_comment_rating_hours});
		} else {
		    $rate_form = $S->_rating_form($curr_rating, $cid);
		}
		if ($rate_form) {
			$comm_options .= qq|\|| if ($comm_options);
			$comm_options .= qq|$rate_form|;
		}
	}
	
	my ($user_info, $edit_user, $comment_ip);
	if ($aid != -1) {
		my $nick = $S->urlify($S->get_nick_from_uid($aid));
		$user_info = qq|(<a href="%%rootdir%%/user/$nick">User Info</a>)|;
		if ($S->have_perm('edit_user')) {
			$edit_user = qq| [<a href="%%rootdir%%/user/$nick/edit">Edit User</a>]|;
		}
	}

	# display the IP that the user posted the comment with
	if ($view_comment_ip
			&& $S->{UI}->{VARS}->{view_ip_log}
			&& $S->{UI}->{VARS}->{comment_ip_log}) {
		#$user_info .= " Poster's IP: ";
		#$user_info .= $comment->{commentip} || 'unknown';
		$comment_ip .= qq| <a href="/iplookup/$comment->[15]">*</a> | || 'unknown';
		
	}
	
	my $new = '';
	# Check for highest index
	if (($S->{UI}->{VARS}->{show_new_comments} eq 'all') && !$check_archivestatus && $op ne 'update') {
		
		if ($S->{UI}->{VARS}->{use_static_pages} && $S->{GID} eq 'Anonymous') {
			#$new = '%%new_'.$cid.'%%';
		} elsif ($S->{UID} >= 0 and ($cid > $story_highest_index)) {
			$new = $S->{UI}->{BLOCKS}->{new_comment_marker};
		}
	} elsif ($op eq 'update' && $detail ne 'c') {
		# sort of weird, but adds the "new" marker to all comments
		# on summary and full detail update pages, but not comment
		# updates
		$new = $S->{UI}->{BLOCKS}->{new_comment_marker};
		}

	my $action;
	if ($comm_options) {
		$action .= qq|[ $comm_options ]|;
	}
	
	if ($comment_delete && !$posting_comment) {
		my $delete = $S->{UI}->{BLOCKS}->{comment_delete_link};
		   $delete =~ s/%%sid%%/$sid/g;
		   $delete =~ s/%%cid%%/$cid/g;
		$action .= $delete;
	}
	if ($comment_remove && !$posting_comment) {
		my $remove = $S->{UI}->{BLOCKS}->{comment_remove_link};
		   $remove =~ s/%%sid%%/$sid/g;
		   $remove =~ s/%%cid%%/$cid/g;
		$action .= $remove;
	}
	if ($comment_toggle && !$posting_comment) {
		my $toggle = 'toggle_normal';
		   $toggle = 'toggle_editorial' unless $comment->[12];
		my $t_link = $S->{UI}->{BLOCKS}->{comment_toggle_link};
		   $t_link =~ s/%%sid%%/$sid/g;
		   $t_link =~ s/%%cid%%/$cid/g;
		   $t_link =~ s/%%toggle%%/$toggle/g;
		$action .= $t_link;
	}

	if (($dispmode eq 'minimal' || $dispmode eq 'dminimal') && (!$alone_mode && !$preview_mode) && $cgi_pid == 0 && (!$cgi_cid || $cgi_cid != $cid)) {
		my $replyblock;
		   $replyblock = qq|$replies| if ($replies && $replies ne '&nbsp;');
		my $item_start_subst = $item_start;
		   $item_start_subst =~ s/!cid!/$cid/g;

		my $this_comment = 
			$item_start_subst .
			$S->_get_comment_subject($sid, $cgi_pid, $dispmode, $comment) .
			$item_end .
			$replyblock;
	
		return $this_comment;
	}
	
	my $this_comment = ($is_shrink_mode && (!$alone_mode && !$preview_mode)) ? $S->{UI}->{BLOCKS}->{comment_collapsed} : $S->{UI}->{BLOCKS}->{comment};
	   $this_comment = $S->{UI}->{BLOCKS}->{moderation_comment} if ($comment->[12]);

	my $member = $S->{UI}->{BLOCKS}->{"mark_$user->{perm_group}"};

	# See if we can help along the validation process...
	# commented these out, because they seem stupid to me. don't see the point
	# in throwing out a perfectly good paragraph tag
	#$comment->{comment} =~ s/^\s*<p>//gi;
	#$comment->{comment} =~ s/^\s*<br>//gi;
	#$comment->{comment} =~ s/<P>/<BR><BR>/gi;
	#$comment->{comment} =~ s/<\/P>//gi;

	$this_comment =~ s/%%uid%%/$aid/g;
	$this_comment =~ s/%%edit_user%%/$edit_user/g;
	$this_comment =~ s/%%name%%/$user->{nickname}/g;
	$this_comment =~ s/%%date%%/$comment->[3]/g;
	$this_comment =~ s/%%subject%%/$comment->[6]/g;
	$this_comment =~ s/%%new%%/$new/g;
	$this_comment =~ s/%%member%%/$member/g;
	$this_comment =~ s/%%pid%%/$pid/g;
	
	my($sig, $comment_text);
	$comment_text = $comment->[7];
	# check for sig behavior and act accordingly
	if ($user->{prefs}->{sig}) {
		#$user->{sig} =~ s/<p>/<br \/><br \/>/gi;
 		#$user->{sig} =~ s/<\/p>//gi;
		# don't use sig behavior, tentatively removing for now
		#if ($comment->{sig_behavior} eq 'retroactive' || $comment->[13] == 1) {
		if ($comment->[13] == 1) {
			#if normal sig, then proceed as usual
			$sig = qq|<p class="sig">$user->{prefs}->{sig}</p>|;

		#} elsif ($comment->{sig_behavior} eq 'sticky' || $comment->{sig_status} == 0) { 
		} elsif ($comment->[13] == 0) {
			#if sticky sig and in preview mode, then place sig below comment
			$sig = $comment->[14];

		} else {
			#the user has a sig but doesn't want it shown
			$sig = "";

		}
	} else {
		$sig = "";
	}
	if (exists($S->{UI}->{VARS}->{use_macros}) && $S->{UI}->{VARS}->{use_macros}) {
		$comment_text = $S->process_macros($comment_text,'comment');
		$sig = $S->process_macros($sig,'pref') if ($sig);
	}

	# figure out which kind of rating display to use.
	my $points;  # keep the old names for these variables to make life a 
	my $numrate; # little easier
	# ... and stuff for the weird new rating list
	my $creclist;
	my $ctrolllist;
	my $listblock;
	# hopefully this does what it should.
	if (defined($comment->[18])) {			# if has raters
		$points  = "$comment->[16]+";
		$numrate = "$comment->[17]-";
		$listblock		= $S->{UI}->{BLOCKS}->{rating_list};
		my $recblock	= $S->{UI}->{BLOCKS}->{recommend_raters};
		my $trollblock	= $S->{UI}->{BLOCKS}->{troll_raters};
		require Storable;
		my $recarr = Storable::thaw(MIME::Base64::decode($comment->[18]));
		foreach my $r (@{$recarr}) {
			my $ratelink = qq~<a href="/user/uid:$r->{uid}">$r->{nick}</a>,\n~;
			if ($r->{rating} == 0) {
				$ctrolllist .= $ratelink;
			} elsif ($r->{rating} == 4) {
				$creclist   .= $ratelink;
			} else {						# shouldn't ever get here, but you never know
				warn "WTF: $cid in $sid had a rating of $r->{rating}, and it shouldn't.\n";
			}
		}
		$ctrolllist =~ s/,$//;
		$creclist   =~ s/,$//;
		if ($ctrolllist) {
			$trollblock =~ s/%%trollraters%%/$ctrolllist/;
			$listblock  =~ s/__TROLLRATE__/$trollblock/;
		} else {
			$listblock  =~ s/__TROLLRATE__//;
		}
		if ($creclist) {
			$recblock   =~ s/%%recraters%%/$creclist/;
			$listblock  =~ s/__RECRATE__/$recblock/;
		} else {
			$listblock  =~ s/__RECRATE__//;
		}
		$listblock = '' unless ($ctrolllist || $creclist);
		#warn "$listblock\n";
		
	} elsif (defined($comment->[16])) {
		$points  = "$comment->[16]";
		$numrate = "$comment->[17]";
	} else {
		$points  = $comment->[9];
		$numrate = $comment->[10];
	}
	
	# harumph
	my $rating_format = ($is_shrink_mode && (!$alone_mode && !$preview_mode)) ? 'rating_format_shrink' : 'rating_format';
	$this_comment =~ s/%%sig%%/$sig/g;
	$this_comment =~ s/%%rating_format%%/$S->{UI}->{BLOCKS}->{$rating_format}/g unless $rate eq 'hide';
	$this_comment =~ s/%%rating_format%%//g; # If not already replaced in previous line, then remove the ey altogether
	$this_comment =~ s/%%comment%%/$comment_text/g;
	$this_comment =~ s/%%cid%%/$cid/g;
	$this_comment =~ s/%%actions%%/$action/g;
	$this_comment =~ s/%%comment_ip%%/$comment_ip/g;
	$this_comment =~ s/%%sid%%/$sid/g;
	$this_comment =~ s/%%score%%/$points/g unless $rate eq 'hide';
	$this_comment =~ s/%%num_ratings%%/$numrate/g unless $rate eq 'hide';
	$this_comment =~ s/%%recommend_list%%/$listblock/g;
	
	if ($user->{fakeemail}) {
		$this_comment =~ s/%%email%%/(<a href="mailto:$user->{fakeemail}">$user->{fakeemail}<\/a>)/g;
	} else {
		$this_comment =~ s/%%email%%//g;
	}
	if ($user->{homepage}) {
		$this_comment =~ s/%%url%%/<a href="$user->{homepage}">$user->{homepage}<\/a>/g;
	} else {
		$this_comment =~ s/%%url%%//g;
	}
	
	# In dynamic modes, add the dynamic collapse link
	if (!$dynamic && !$preview_mode && ($dispmode eq 'dthreaded' || $dispmode eq 'dminimal')) {
		my $item_start_subst = $item_start;
		   $item_start_subst =~ s/!cid!/$sid/g;
		$this_comment = $item_start_subst . $this_comment;
		if ($alone_mode && !$preview_mode) {
			$this_comment .= $item_end;
		} else {
			$replies = $item_end . $replies;
		}
	}

	$this_comment =~ s/%%replies%%/$replies/g
		if (!$alone_mode && !$preview_mode);

	return $this_comment;
}


# is this sub even used anymore? it doesn't seem to be
sub comment_choices_box {
	my $S = shift;
	my $sid = shift;
	my $pid = $S->{CGI}->param('pid');
	my $cid = $S->{CGI}->param('cid');
	
	my $commentmode_select = $S->_comment_mode_select();
	my $comment_order_select = $S->_comment_order_select();
	my $comment_rating_select = $S->_comment_rating_select();
	my $rating_choice = $S->_comment_rating_choice();
	my $comment_type_select = $S->_comment_type_select();
	
	my $form_op = 'op';
	my $form_op_value = 'displaystory';
	my $id = 'sid';
	
	if ($S->_does_poll_exist($sid)) {
		$form_op       = 'op';
		$form_op_value = 'view_poll';
		$id 		   = 'qid';
	}
		
	my $comment_sort = qq|
			<FORM NAME="commentmode" ACTION="%%rootdir%%/" METHOD="post">
		<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0 WIDTH="100%" BGCOLOR="%%box_content_bg%%">
			<INPUT TYPE="hidden" NAME="$form_op" VALUE="$form_op_value">
			<INPUT TYPE="hidden" NAME="$id" VALUE="$sid">
		
			<TR>
				<TD VALIGN="middle">
					%%norm_font%%
						View:
					%%norm_font_end%%
				</TD>
				<TD VALIGN="top">
					%%norm_font%%<SMALL>
						$comment_type_select
					</SMALL>%%norm_font_end%%
				</TD>
			</TR>
		
		<TR>
			<TD VALIGN="middle">
				%%norm_font%%
					Display:
				%%norm_font_end%%
			</TD>
			<TD>
			%%norm_font%%<SMALL>
				$commentmode_select
			</SMALL>%%norm_font_end%%
			</TD>
		</TR>
		
		<TR>
			<TD VALIGN="middle">
				%%norm_font%%
					Sort:
				%%norm_font_end%%
			</TD>
			<TD VALIGN="top">
				%%norm_font%%<SMALL>
					$comment_rating_select
				</SMALL>%%norm_font_end%%
			</TD>
		</TR>
		<TR>
			<TD>
				%%norm_font%%&nbsp;%%norm_font_end%%
			</TD>
			<TD>
				%%norm_font%%<SMALL>
					$comment_order_select
				</SMALL>%%norm_font_end%%
			</TD>
		</TR>
	|;
		
			
	if ($S->have_perm( 'comment_rate' )) {
		$comment_sort .= qq|
		<TR>
		<TD VALIGN="middle">%%norm_font%%
		Rate?
		%%norm_font_end%%
		</TD>
		<TD VALIGN="top">%%norm_font%%
		<SMALL>$rating_choice</SMALL>
		%%norm_font_end%%
		</TD>
		</TR>|;
	}
	
	$comment_sort .= qq|
	<TR><TD COLSPAN=2 ALIGN="right">%%norm_font%%<INPUT TYPE="submit" NAME="setcomments" VALUE="Set">%%norm_font_end%%</TD></TR>
	</TABLE>
	</FORM>|;

	my $box = $S->make_box("Comment Controls", $comment_sort);
	return $box;
}

sub comment_controls {
	my $S = shift;
	my $sid = shift;
	my $pid = $S->{CGI}->param('pid');
	my $cid = $S->{CGI}->param('cid');
	my $caller = $S->cgi->param('caller_op');
	my $op = $S->cgi->param('op');

	return '';
	
	# don't even bother if they don't have permission to view the story,
	# BUT! let them see this if they have post permissions.  never know how someone
	# would set this up, but if they want to allow posting but not reading, eh.
	my $section = $S->_get_story_section($sid);
	return '' unless( $S->have_section_perm('norm_read_comments', $section )	|| 
						( $S->_does_poll_exist($sid)	&& 
						( $S->have_perm('poll_read_comments') || $S->have_perm('poll_post_comments') )) );
	
	# special dkos thing. nip this in the bud more easily.
	return '';

	my $s_info = $S->{UI}->{BLOCKS}->{story_info};
	
	my $commentstatus = $S->_check_commentstatus($sid);

	my $story_info_txt = '';
	my $q_sid = $S->dbh->quote($sid);
	unless ( $S->_does_poll_exist($sid) ) {
		my ($rv, $sth) = $S->db_select({
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'title',
			FROM => 'stories',
			WHERE => qq|sid = $q_sid|
			});

		(my $story_info = $sth->fetchrow_hashref);
		$sth->finish;

		my $linktitle = ($caller eq 'storyonly' || $op eq 'view_poll') ? 'View Comments' : 'Permalink';
		my $storyop = ($caller eq 'storyonly' || $op eq 'view_poll') ? 'story' : 'storyonly';
		$story_info_txt = qq|<a href="%%rootdir%%/$storyop/$sid">$linktitle</a> |;
		# link to set 'diarylink' pref
		my $dlink = $S->pref('diarylink') || 'storyonly';
		my $diarylink;
		if($S->have_perm('comment_post') && $section eq	'Diary'){
			my $switch = ($dlink eq 'storyonly') ? 'story' : 'storyonly';
			my $switchlink = qq|<a href="%%rootdir%%/storylink/$sid/$switch">|;
			my $switchtitle = ($dlink eq 'storyonly') ? 'Default View Comments' : 'Default Story Only';
			$diarylink = " | $switchlink$switchtitle</a>";
			}
		$story_info_txt .= $diarylink;
		# don't display comment stats if comments are disabled
		unless (($commentstatus == -1) || ($S->have_section_perm('hide_read_comments', $section))) {
			my ($topical,  $editorial, $review) = $S->_comment_breakdown($sid);
			$story_info->{commentcount} = ($topical + $editorial);
			my $r_inf;
			if ($S->{UI}->{VARS}->{use_mojo}) {
				#warn "Review is $review\n";
				$r_inf = ", $review hidden";
			}

			my $plural = ($story_info->{commentcount} == 1) ? '' : 's';
			$story_info_txt .= qq|\| <B>$story_info->{commentcount}</B> comment$plural |;
		}

	} else {
		my $comment_num = $S->poll_comment_num($sid);
		my $poll_q = $S->get_poll_hash($sid);

		# put a link to the poll in there, since if they are here they can see it, and know what its attached to
		$story_info_txt = qq|<a href="%%rootdir%%/poll/$sid">$poll_q->{question}</a>|;

		# now if they can read the comments too, put the comment count
		if( $S->have_perm('poll_read_comments') ) {
			$story_info_txt .= qq| \| <b>$comment_num</b> comments |;
		}

	}

	# only give Post Comment link if commentstatus is zero (Comments Enabled)
	unless ($commentstatus) {
		if ($S->have_perm('comment_post')) {
			if ($S->_check_archivestatus($sid)) {
				$story_info_txt .= "| Cannot post in Archive ";
			} else {
				$story_info_txt .= qq|\| <A HREF="%%rootdir%%/comments/$sid/0/post#here"><B>Post A Comment</B></A> | 
			if ($S->have_section_perm('norm_post_comments',$section) && !$S->_does_poll_exist($sid) && $caller ne 'storyonly');

				$story_info_txt .= qq|\| <A HREF="%%rootdir%%/comments/poll/$sid/0/post#here"><B>Post A Comment</B></A> | 
			if ($S->_does_poll_exist($sid) && $S->have_perm('poll_post_comments'));
			}
		}
	}
	if ($S->_does_poll_exist($sid) && $S->have_perm('edit_polls')) {
		$story_info_txt .= qq|\| <a href="%%rootdir%%/admin/editpoll/$sid">Edit Poll</a>|;
	} elsif (!$S->_does_poll_exist($sid) && $S->check_edit_story_perms($sid)) {
		$story_info_txt .= qq|\| <a href="%%rootdir%%/admin/story/$sid">Edit Story</a>|;
	}

	$s_info =~ s/%%story_info%%/$story_info_txt/;
	
	return $s_info;
}


sub _comment_mode_select {
	my $S = shift;
	my $mode = $S->get_comment_option('commentmode');
	
	my ($selected_n, $selected_f, $selected_m, $selected_dt, $selected_dm, $selected_u);
	if ($mode eq 'nested') {
		$selected_n = ' SELECTED';
	} elsif ($mode eq 'flat') {
		$selected_f = ' SELECTED';
	} elsif ($mode eq 'minimal') {
		$selected_m = ' SELECTED';
	} elsif ($mode eq 'flat_unthread') {
		$selected_u = ' SELECTED';
	} elsif ($S->{UI}->{VARS}->{allow_dynamic_comment_mode} && $S->pref('dynamic_interface') eq 'on') {
		if ($mode eq 'dthreaded') {
			$selected_dt = ' SELECTED';
		} elsif ($mode eq 'dminimal') {
			$selected_dm = ' SELECTED';
		}
	}
	
	my $select = qq|<SELECT NAME="commentmode" SIZE=1>
		<OPTION VALUE="threaded">Threaded
		<OPTION VALUE="minimal"$selected_m>Minimal
		<OPTION VALUE="nested"$selected_n>Nested
		<OPTION VALUE="flat"$selected_f>Flat
		<OPTION VALUE="flat_unthread"$selected_u>Flat Unthreaded|;
	if ($S->{UI}->{VARS}->{allow_dynamic_comment_mode} && $S->pref('dynamic_interface') eq 'on') {
		$select .= qq|<OPTION VALUE="dthreaded"$selected_dt>Dynamic Threaded|;
		$select .= qq|<OPTION VALUE="dminimal"$selected_dm>Dynamic Minimal|;
	}
	$select .= qq|</SELECT>|;
	
	return $select;
}

sub _comment_type_select {
	my $S = shift;
	my $type = $S->get_comment_option('commenttype');
	
	return '' unless $S->have_perm('editorial_comments');

	my ($editorial_s, $all_s, $none_s, $topical_s);
	
	if ($type eq 'editorial') {
		$editorial_s = ' SELECTED';
	} elsif ($type eq 'all') {
		$all_s = ' SELECTED';
	} elsif ($type eq 'none') {
		$none_s = ' SELECTED';
	} elsif ($type eq 'topical') {
		$topical_s = ' SELECTED';
	}
	
	
	my $select = qq|<SELECT NAME="commenttype" SIZE=1>
		<OPTION VALUE="mixed">Mixed (default)
		<OPTION VALUE="topical"$topical_s>Topical Only
		<OPTION VALUE="editorial"$editorial_s>Editorial Only
		<OPTION VALUE="all"$all_s>All Comments
		<OPTION VALUE="none"$none_s>No Comments</SELECT>|;
	
	return $select;	
}

sub _comment_order_select {
	my $S = shift;
	my $order = $S->get_comment_option('commentorder');
	
	my ($selected_o);
	if ($order eq 'oldest') {
		$selected_o = ' SELECTED';
	} 
	
	my $select = qq|<SELECT NAME="commentorder" SIZE=1>
		<OPTION VALUE="newest">Newest First
		<OPTION VALUE="oldest"$selected_o>Oldest First
		</SELECT>|;
	
	return $select;
} 


sub _set_comment_mode {
	my $S = shift;
	my $count = shift;
	return unless $count;
	
	# Dynamic subthreads should always be dynamic themselves
	if($S->{UI}->{VARS}->{allow_dynamic_comment_mode} && ($S->{CGI}->param('op') eq 'dynamic')) {
		return 'dynamic';
	}

	my $thismode = $S->cgi->param('commentmode');
	if ($thismode) {
		$S->session('commentmode', $thismode);
		return;
	}
	
	return unless ($S->{SESSION_KEY});

	my $mode = $S->pref('commentmode');
	my $overflow = $S->pref('commentmode_overflow');
	my $overflow_at = $S->pref('commentmode_overflow_at');
	my $return;

	if ( $count > $overflow_at || $mode eq 'use_overflow' ) {
		$return = $overflow;
	} else {
		$return = $mode;
	}
	
	$S->session('commentmode', $return);
	return;
}

sub comment_toggle_pending {
	#mostly verbatim from Elby's Adequacy code
	my $S = shift;
	my $sid = shift;
	my $cid = shift;
	my $tool = shift;

	if ($tool eq 'toggle_editorial') {
		$tool = 1;
	} else {
		$tool = 0;
	}
	if ($S->have_perm('comment_delete')) {
		my ($change, $pending) = $S->_findchildren($sid, $cid);

		my $where = qq|(sid = "$sid") and (cid = $cid|;
		foreach my $cid (@$change) {
			$where .= " or cid = $cid";
		}
                $where .= ")";


		my ($rv, $sth) = $S->db_update({
			DEBUG	=> 0,
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT	=> 'comments',
			SET	=> "pending=$tool",
			WHERE   => $where});
		$sth->finish;

                push @{ $change }, $cid;
		$S->{UI}->{BLOCKS}->{TOP_CONTENT} = "The following comments were changed from " 
			. ($pending ? "Editorial" : "Topical") . " to " 
			. ($pending ? "Topical" : "Editorial") . ": " . (join ", ", @$change) . "\n<P>";
		$S->_count_cache_drop($sid);
                $S->run_hook('comment_toggle', $sid, $cid, $tool);
	}
}

# icky recursion
sub _findchildren {
	# verbatim from Elby's adequacy code (except re-formating by panner)
	my $S = shift;
	my $sid = shift;
	my $cid = shift;
	my $has_parent = shift || [];
	my @cid;

	if (scalar @$has_parent) {
		foreach my $comment (@{ ${$has_parent}[$cid] }) {
			@cid = (
				$comment->{cid},
				@cid,
				$S->_findchildren($sid, $comment->{cid}, $has_parent)
			);
		}
		return @cid;
	} else { 
		my @has_parent;
		my $pending;

		my $q_sid = $S->dbh->quote($sid);
		my ($rv, $sth) = $S->db_select({
        	DEBUG => 0,
			ARCHIVE => $S->_check_archivestatus($sid),
			WHAT => 'pending, cid, pid',
			FROM => 'comments',
			WHERE => qq|sid = $q_sid|
		});

		while (my ($s_pending, $s_cid, $s_pid) = $sth->fetchrow()) {
			push @{ $has_parent[$s_pid] }, {
				cid => $s_cid, pid => $s_pid, pending => $s_pending
			};
			if ($s_cid == $cid) {
				$pending = $s_pending;
			}
		}
		@cid = $S->_findchildren($sid, $cid, \@has_parent);
		return (\@cid, $pending);
	}
}

1;
