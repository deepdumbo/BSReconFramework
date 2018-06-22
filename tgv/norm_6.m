
function [norm3] = norm_6(v)

	
	norm3 = sqrt(     v(:,:,:,1).^2 +   v(:,:,:,2).^2 +   v(:,:,:,3).^2 + ...
			2*v(:,:,:,4).^2 + 2*v(:,:,:,5).^2 + 2*v(:,:,:,6).^2  );


end
