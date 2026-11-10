-- Remove post_participant_tag notifications inserted by create_shared_post.
-- The matching Swift enum case (postParticipantTag) exists in the codebase but
-- has not shipped yet. Any user with one of these notifications gets a
-- DecodingError that aborts the entire fetchNotifications call.
-- The next app release will handle this type correctly; new notifications
-- created after that release will display normally.
DELETE FROM public.notifications
WHERE type = 'post_participant_tag';
