require 'torch'
require 'image'
require 'paths'

local dataset = {}

-- load data from these directories
dataset.dirs = {}

-- load only images with unique filenames (basenames)
-- i.e. if an image with name "foo.jpg" is in directory "a" and "b" ("a/foo.jpg", "b/foo.jpg"),
-- it will only be loaded once
dataset.uniqueFilenames = true

-- load only images with these file extensions
dataset.fileExtension = "jpg"

-- expected original height/width of images
dataset.originalHeight = 32
dataset.originalWidth = 64
-- desired height/width of images
dataset.height = 16
dataset.width = 32
-- desired channels of images (1=grayscale, 3=color)
--dataset.nbChannels = 3
dataset.colorSpace = "rgb"

-- cache for filepaths to all images
dataset.paths = nil

-- Set directories to load images from
-- @param dirs List of paths to directories
function dataset.setDirs(dirs)
  dataset.dirs = dirs
end

-- Set file extension that images to load must have
-- @param fileExtension the file extension of the images
function dataset.setFileExtension(fileExtension)
  dataset.fileExtension = fileExtension
end

-- Desired height of the images (will be resized if necessary)
-- @param scale The height of the images
function dataset.setHeight(height)
  dataset.height = height
end

-- Desired height of the images (will be resized if necessary)
-- @param scale The height of the images
function dataset.setWidth(width)
  dataset.width = width
end

-- Set desired number of channels for the images (1=grayscale, 3=color)
-- @param nbChannels The number of channels
function dataset.setNbChannels(nbChannels)
  dataset.nbChannels = nbChannels
end

-- Loads the paths of all images in the defined files
-- (with defined file extensions)
function dataset.loadPaths()
    local files = {}
    local dirs = dataset.dirs
    local ext = dataset.fileExtension
    local added = {}
    local nbIgnored = 0

    for i=1, #dirs do
        local dir = dirs[i]
        local filesInDir = paths.files(dir)
        local containsImages = false
        
        -- Go over all files in directory. We use an iterator, paths.files().
        for file in filesInDir do
            -- We only load files that match the extension
            if file:find(ext .. '$') then
                containsImages = true
                
                -- and insert the ones we care about in our table
                -- insert only if filename was not added yet (same file in another directory)
                -- or if uniqueFilenames is false
                local filename = paths.basename(file)
                local notAddedYet = (added[filename] == nil)
                if notAddedYet or not dataset.uniqueFilenames then
                    table.insert(files, paths.concat(dir,file))
                    added[filename] = true
                else
                    nbIgnored = nbIgnored + 1
                end
            end
        end

        -- Check if empty
        -- filesInDir is an iterator, so we cant just check #filesInDir
        if not containsImages then
            error(string.format("[Dataset] Directory '%s' does not contain any files of type '%s'", dir, ext))
        end
    end
    
    -- sort by filename (not full filepath)
    -- a) for reproduceability
    -- b) so that images of different keywords (directories) follow each other (instead of first
    --    all images of one keyword, then all images of the next keyword...)
    table.sort(files, function (a,b) return paths.basename(a) < paths.basename(b) end)
    
    dataset.paths = files
    print(string.format("[Dataset] Found %d filepaths in %d directories. Ignored %d filepaths because of duplicates.", #files, #dirs, nbIgnored))
end

-- Load images from the dataset.
-- @param startAt Number of the first image.
-- @param count Count of the images to load.
-- @return Table of images. You can call :size() on that table to get the number of loaded images.
function dataset.loadImages(startAt, count)
    local endBefore = startAt + count
    if dataset.paths == nil then
        dataset.loadPaths()
    end

    local N = math.min(count, #dataset.paths)
    local images = torch.FloatTensor(N, 3, dataset.height, dataset.width)
    for i=1,N do
        local img = image.load(dataset.paths[i], dataset.nbChannels, "float")
        img = image.scale(img, dataset.width, dataset.height)
        images[i] = img
        
        if i % 2000 == 0 then
            collectgarbage()
        end
    end
    images = NN_UTILS.rgbToColorSpace(images, dataset.colorSpace)

    local result = {}
    result.data = images
    
    function result:size()
        return N
    end

    setmetatable(result, {
        __index = function(self, index) return self.data[index] end,
        __len = function(self) return self.data:size(1) end
    })

    return result
end

-- Loads a defined number of randomly selected images from
-- the cached paths (cached in loadPaths()).
-- @param count Number of random images.
-- @return List of Tensors
function dataset.loadRandomImages(count)
    local images = dataset.loadRandomImagesFromPaths(count)
    local data = torch.FloatTensor(#images, 3, dataset.height, dataset.width)
    for i=1, #images do
        data[i] = image.scale(images[i], dataset.width, dataset.height)
    end
    data = NN_UTILS.rgbToColorSpace(data, dataset.colorSpace)

    local N = data:size(1)
    local result = {}
    result.scaled = data

    function result:size()
        return N
    end

    function result:normalize(mean, std)
        mean, std = NN_UTILS.normalize(result.scaled, mean, std)
        return mean, std
    end

    setmetatable(result, {
        __index = function(self, index) return self.scaled[index] end,
        __len = function(self) return self.scaled:size(1) end
    })

    return result
end

-- Loads randomly selected images from the cached paths.
-- TODO: merge with loadRandomImages()
-- @param count Number of images to load
-- @returns List of Tensors
function dataset.loadRandomImagesFromPaths(count)
    if dataset.paths == nil then
        dataset.loadPaths()
    end

    local shuffle = torch.randperm(#dataset.paths)    
    
    local images = {}
    for i=1,math.min(shuffle:size(1), count) do
       -- load each image
       table.insert(images, image.load(dataset.paths[shuffle[i]], 3, "float"))
    end
    
    return images
end

return dataset
