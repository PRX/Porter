/**
 * @typedef {object} Payload
 * @property {!Job} Job
 * @property {!Artifact} Artifact
 * @property {!Task} Task
 */

/**
 * @typedef {object} ResultPayload
 * @property {!Job} Job
 * @property {!Artifact} Artifact
 * @property {!Task} Task
 * @property {!VariantResult[]} VariantResults
 * @property {!Orchestration} Orchestration
 */

/**
 * @typedef {object} VariantResult
 * @property {!string} PresetLabel
 * @property {!string} M3U8
 * @property {!VariantMedia} Media
 * @property {!VariantPlaylist} Playlist
 */

/**
 * @typedef {object} Job
 * @property {!string} Id
 */

/**
 * @typedef {object} Artifact
 * @property {!string} BucketName
 * @property {!string} ObjectKey
 * @property {!number} ContentLength
 * @property {!ArtifactDescriptor} Descriptor
 */

/**
 * @typedef {object} ArtifactDescriptor
 * @property {?string} Extension
 * @property {?string} MIME
 */

/**
 * @typedef {object} Task
 * @property {"HLS"} Type
 * @property {!string} Preset
 * @property {!Destination} Destination
 */

/**
 * @typedef {object} Destination
 * @property {!string} Mode
 * @property {!string} BucketName
 * @property {!string} ObjectKeyPrefix
 * @property {object} Parameters
 */

/**
 * @typedef {object} Orchestration
 * @property {!VariantSubtask[]} VariantSubtasks
 * @property {!Preset} Preset
 */

/**
 * @typedef {object} VariantSubtask
 * @property {!string} PresetLabel
 * @property {!string} FileStem
 * @property {!string[]} FFmpegCommandParts
 */

/**
 * @typedef {object} HlsResult
 * @property {"HLS"} Task
 * @property {!Preset} Preset
 * @property {!Assets} Assets
 */

/**
 * @typedef {object} Preset
 * @property {!string} Name
 * @property {!string[]} PossibleLabels
 */

/**
 * @typedef {object} Assets
 * @property {!MasterPlaylist} MasterPlaylist
 * @property {!Variant[]} Variants
 */

/**
 * @typedef {object} MasterPlaylist
 * @property {!string} ObjectKey
 */

/**
 * @typedef {object} Variant
 * @property {!string} PresetLabel
 * @property {!VariantPlaylist} Playlist
 * @property {!VariantMedia} Media
 */

/**
 * @typedef {object} VariantPlaylist
 * @property {!string} ObjectKey
 */

/**
 * @typedef {object} VariantMedia
 * @property {!string} ObjectKey
 * @property {!boolean} IncludesAudioStreams
 * @property {!boolean} IncludesVideoStreams
 */
