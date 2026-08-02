CREATE TABLE `scan_usage` (
	`bucket` text NOT NULL,
	`client_hash` text NOT NULL,
	`scan_count` integer DEFAULT 0 NOT NULL,
	`updated_at` text NOT NULL,
	PRIMARY KEY(`bucket`, `client_hash`)
);
