function pattern = genGaussPattern(sizeData, AF, sigma, numSlice)

lin = round(sizeData(1)*numSlice/AF);

pattern2D = zeros(sizeData(1),sizeData(3));

while sum(pattern2D(:)) ~= lin
pattern2D = zeros(sizeData(1),sizeData(3));
numlin = ceil(lin*1.16);
linesY = round(randn(numlin,1)*sigma(1));
linesZ = round(randn(numlin,1)*sigma(2));
y = repmat(sizeData(1)/2,1,size(linesY,1))+linesY';
z = repmat(sizeData(3)/2,1,size(linesY,1))+linesZ'; 
y = min(y,repmat(sizeData(1),1,size(linesY,1)));
y = max(y,ones(1,size(linesY,1)));
z = min(z,repmat(sizeData(3),1,size(linesY,1)));
z = max(z,ones(1,size(linesY,1)));
for it = 1:size(linesY,1)
    pattern2D(y(it),z(it)) = 1;
end
end

pattern = reshape(pattern2D, [sizeData(1), 1, sizeData(3)]);
pattern = repmat(pattern, [1, sizeData(2), 1, sizeData(4), sizeData(5)]);

