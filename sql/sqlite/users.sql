CREATE TABLE `users` (
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT
,  `name` char(255) NOT NULL
,  `password` char(255) DEFAULT NULL
,  `change_password` integer DEFAULT 1
,  `is_admin` integer DEFAULT 0
,  `is_temporary` integer DEFAULT 0
,  `is_disabled` integer DEFAULT 0
,  UNIQUE (`name`)
);
